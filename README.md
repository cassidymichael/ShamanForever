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

### The "no shield" look, and the one inference ShamanForever makes

Blizzard's button hides when the aura is gone, but addon code has no sanctioned way to learn that in combat. Tested on build 69913 (2026-09-23):

- every `C_UnitAuras` call throws for addon code in combat, including `GetAuraDuration` and `GetUnitAuraInstanceIDs`, which are not flagged secret in the API docs;
- `UNIT_AURA` stops reaching the addon in combat;
- script handlers under the button never run, and the button only plays animations on its own descendants, which hide with it.

So the grey icon, red ring and pulse sit in an underlay beneath Blizzard's button, driven by a belief:

- **Out of combat** it is exact, read from the aura.
- **In combat** your own successful Lightning Shield cast (`UNIT_SPELLCAST_SUCCEEDED`) sets it to "up". Your own cast events are documented as never secret; only other units' casts are restricted. The combat log is never read. The inference is only that a successful cast means the shield is up.
- **Nothing can set it to "down" in combat.** If the shield drops mid-fight, the underlay shows at the "No shield: combat fallback" strength until you recast or combat ends.
- **Why keep it:** without it, entering combat with no shield and casting one mid-fight would leave the full "no shield" look showing through the live shield until combat ends, whenever the group opacity is below 100%.

The underlay matters only because a group opacity below 100% makes Blizzard's button translucent, so the underlay would show through it. The addon fades the underlay while the shield is believed up, and Blizzard's icon opacity is raised to compensate so the stack matches the group's opacity. At 100% group opacity the button covers the underlay completely.

## Timers and warnings in combat without reading secrets

Totem and cooldown elements never read a secret value. They hand Blizzard's objects to Blizzard's widgets:

- **Cooldowns and totem timers:** `C_Spell.GetSpellCooldownDuration` and `GetTotemDuration` return duration objects, which `Cooldown:SetCooldownFromDurationObject` and `StatusBar:SetTimerDuration` draw.
- **Appear/disappear on a secret condition:** a duration object evaluates its remaining or total time through a `C_CurveUtil` curve, and the (possibly secret) result goes straight to `SetAlpha`. Fire Nova's "no fire totem" warning is a curve on the fire slot's remaining time (0 s → shown). An empty slot returns no duration object at all, which is plainly "no totem".
- **Which earth totem is out:** in combat everything `GetTotemInfo` returns is secret, so Earthbind and Stoneclaw identify their timer by its total duration: a curve that is 1 only within half a second of that totem's lifetime (45 s and 15 s, learned out of combat). This assumes no two earth totems share a lifetime, which holds for vanilla.

Weapon imbues are item data (`C_Item.GetWeaponEnchantInfo`, enchant type `Imbue`) and stay readable in combat.


## Releases

Releases are built by the BigWigs packager on tag push; see `.github/workflows/release.yml`.

## Licence

MIT, see LICENSE. 
