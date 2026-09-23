# ShamanForever

A small HUD for shamans on World of Warcraft: Forever.

> This quick addon was created by AI, with minimal oversight by a human. Feedback and requests are welcome.

![ShamanForever HUD: Lightning Shield with charge bar next to the shock icon](screenshot.png)

- **Lightning Shield**: icon, charge number and a segmented charge bar, exact in combat. The buff is drawn by Blizzard's secure aura container, so it is not subject to the addon aura restrictions. When the shield is down the icon greys out and, once combat ends, gets a red ring.
- **Shock**: the shock of your choice (Earth, Flame or Frost, highest rank known) with its cooldown and countdown, red when your target is out of range, blue with a blue ring when you cannot afford it.

- **Layout**: elements are arranged in groups. Each group is a row or column with its own position, scale and opacity; an element can sit alone, share a group, or be hidden.

Options: `/sf` (alias `/shf`) opens the options window; Escape > Options > AddOns > Shaman Forever has a button to it. `/sf unlock` and `/sf lock` toggle on-screen arranging:

- drag a group to move it; it snaps to the grid and to other groups' edges and centres (off by default: switch on Snapping and Show grid in the unlock bar or on the Layout page)
- mouse wheel over a group for scale, shift + wheel for opacity
- right-click a group to open its settings

Which elements share a group is set on the options window's Layout page: drag an element onto another group or New group, or click it for a menu. When each element shows (Always, In combat, Never) is set on the Elements page.

`/sf test` adds placeholder elements for trying out layouts; `/sf debug` prints diagnostics.

Requires interface 16001 (WoW: Forever). Settings live in `ShamanForeverDB`.

> **Beta caveat, not specific to this addon:** the Forever client writes SavedVariables on logout but never loads them again, so every addon's settings reset to their defaults when you restart the client. Within a session `/reload` keeps them, which is why it can look fine until you quit. Blizzard has not fixed it yet; community workarounds such as [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix) restore them in the meantime.

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


## Releases

Releases are built by the BigWigs packager on tag push; see `.github/workflows/release.yml`.

## Licence

MIT, see LICENSE. 
