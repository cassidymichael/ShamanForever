# Combat techniques

How ShamanForever shows state in combat on WoW: Forever, where addon code cannot read most combat data (Midnight "secret values"). The rule throughout: never do Lua math or comparisons on a possibly-secret value; hand Blizzard's objects to Blizzard's widgets instead. Findings are from build 69913 and are dated where they matter.

## Showing auras: Blizzard's CustomAuraContainer

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

## The "no shield" look, and the one inference ShamanForever makes

Blizzard's button hides when the aura is gone, but addon code has no sanctioned way to learn that in combat. Tested on build 69913 (2026-09-23):

- every `C_UnitAuras` call throws for addon code in combat, including `GetAuraDuration` and `GetUnitAuraInstanceIDs`, which are not flagged secret in the API docs;
- `UNIT_AURA` stops reaching the addon in combat;
- script handlers under the button never run, and the button only plays animations on its own descendants, which hide with it.

So the grey icon, red ring and pulse sit in an underlay beneath Blizzard's button, driven by a belief:

- **Out of combat** it is exact, read from the aura.
- **In combat** your own successful cast of a tracked shield (`UNIT_SPELLCAST_SUCCEEDED`) sets it to "up". Your own cast events are documented as never secret; only other units' casts are restricted. The combat log is never read. The inference is only that a successful cast means that shield is up. Since only one elemental shield can be on you at a time, casting a shield you don't track sets it to "down".
- **Nothing can set it to "down" in combat.** If the shield drops mid-fight, the underlay shows at the "No shield: combat fallback" strength until you recast or combat ends.
- **Why keep it:** without it, entering combat with no shield and casting one mid-fight would leave the full "no shield" look showing through the live shield until combat ends, whenever the group opacity is below 100%.

The underlay matters only because a group opacity below 100% makes Blizzard's button translucent, so the underlay would show through it. The addon fades the underlay while the shield is believed up, and Blizzard's icon opacity is raised to compensate so the stack matches the group's opacity. At 100% group opacity the button covers the underlay completely.

## Timers and warnings in combat without reading secrets

Totem and cooldown elements never read a secret value. They hand Blizzard's objects to Blizzard's widgets:

- **Cooldowns and totem timers:** `C_Spell.GetSpellCooldownDuration` and `GetTotemDuration` return duration objects, which `Cooldown:SetCooldownFromDurationObject` and `StatusBar:SetTimerDuration` draw.
- **Appear/disappear on a secret condition:** a duration object evaluates its remaining or total time through a `C_CurveUtil` curve, and the (possibly secret) result goes straight to `SetAlpha`. Fire Nova's "no fire totem" warning is a curve on the fire slot's remaining time (0 s → shown). An empty slot returns no duration object at all, which is plainly "no totem".
- **Which earth totem is out:** in combat everything `GetTotemInfo` returns is secret, but our own `UNIT_SPELLCAST_SUCCEEDED` is not: it gives the spell, in the same frame as the `PLAYER_TOTEM_UPDATE` that fills the slot. So the totem in a slot is the last totem we cast into it (slots by name from `GetMultiCastTotemSpells`), and Earthbind and Stoneclaw show their timer only when it is theirs. Call of the Elements reports each totem it drops as its own cast, so it binds the same way. When that is unknown (a `/reload` with a totem already out), out of combat the slot's name decides, and in combat the slot's total duration through a curve that is 1 only near that totem's lifetime (45 s, 15 s; every other earth totem lasts 5 min on Forever). Lifetimes are not learned from the slot: right after a cast it can pair the old totem's name with the new totem's duration.

Weapon imbues are item data (`C_Item.GetWeaponEnchantInfo`, enchant type `Imbue`) and stay readable in combat.

## The totem bar in combat

Secure snippets don't run on Forever, so every click goes through one of Blizzard's built-in secure actions, set up out of combat:

- **Dismiss:** a `SecureActionButtonTemplate` button with `*type2 = "destroytotem"` and `totem-slot`. Attributes use the `*` form (`*type2`, `*type1`): a plain `type2` is only used when no modifier key is held.
- **Cast the element's pick:** `*type1 = "action"` on the element's multi-cast action slot (the one Blizzard's Totem Action Bar and Call of the Elements use), so it follows the pick wherever it is changed.
- **Open a picker, in combat too:** Blizzard's `SecureStateDriverManager` takes its instructions as attributes (`setframe`, then `setstate` = `"state-visibility show"`), and the built-in `attribute` action can set them. A button with `pressAndHoldAction` runs its `type` action on press and its `typerelease` action on release, so one click does both writes: the arrow tab (and Alt+click on a slot) names the picker on press and shows it on release. The picker's buttons use `multispell` (spell `0` is "No totem"), then hide the picker on release; an invisible screen-wide button inside the picker closes it on any other click.
- **Which totem is down:** the slot's icon is secret in combat, but `SetTexture` accepts the secret value and draws it. Timers come from `GetTotemDuration`, and the expiring warning and "not your pick" badge follow the same rules as above (curves into `SetAlpha`; our own casts for the totem's name, matched without its rank).
- **Layout** (showing, hiding, moving the bar's buttons) only changes out of combat; changes made in combat wait for it to end.
- **Call of the Elements and Totemic Recall:** plain `type = "spell"` buttons. Recall's right-click dismisses every totem without a spell: a secure button does one action per click, so it runs a macro that `/click`s four `destroytotem` helpers (`/click` sends a release, so they act on release). The key bindings are `CLICK` bindings to invisible buttons of their own (Bindings.xml).
- **Killed early and ran out:** when a slot empties, its last duration object still says how much time the totem had left. It goes through a curve into a flash's `SetAlpha`: one curve shows the red "killed early" flash only with more than 1.25 s left, the opposite curve shows the "ran out" pop only up to 1.2 s. Our own dismissals are left out: every one goes through `DestroyTotem` (`hooksecurefunc`), and Totemic Recall is our own cast.

## Glows and pops

- **Two secret conditions at once** (Fire Nova's ready glow: off cooldown *and* a fire totem down): each drives the alpha of one of two nested frames, and nested alphas multiply.
- **Pop when a cooldown is ready:** the Cooldown widget's `OnCooldownDone` script fires when its swipe finishes, a moment with nothing secret in it.
- **Pop when an imbue drops:** imbues are readable, so the change is seen directly.

