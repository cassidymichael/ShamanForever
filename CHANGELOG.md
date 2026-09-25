# Changelog

## 0.6.1 (2026-09-25)

- Fixed: after restarting the game, a character could load the Default profile instead of its own.
- Fixed: icons popped after every cast (the global cooldown), and "Pulsing glow when ready" blinked off during it.
- Pulsing glows now sit inside the icon, running in from its edges, so they show at any icon opacity. Set colour, pulse length, pulse depth and thickness on the General page, with a live preview.
- Pops have their own settings on the General page: motion (grow, bounce, hop, or shake side to side or up and down), how far and how fast, plus an optional flash, ring burst and star burst, coloured by what happened. A test icon plays your choice. The new default is a shake up and down with a star and a flash.
- Totem bar: "Not your pick" has opacity and colour settings.
- Previews in the options use your border settings.

## 0.6.0 (2026-09-25)

- Totem bar is out of experimental. At the top of its page, choose Blizzard's, Active totems (replaces only the totems under the player frame) or Everything (replaces both of Blizzard's totem bars).
- Totem bar: Call of the Elements and Totemic Recall buttons, at both ends of the bar or together before or after the slots, with their own size. Right-click Recall to dismiss every totem (no global cooldown, no mana back), even before you learn it.
- Key bindings (Options > Keybindings > Shaman Forever): cast each element's totem, dismiss each totem or all of them, Call of the Elements, Totemic Recall.
- Killed early: a totem that dies before its time flashes red with a pop, a glow and a cross until you recast it. On the totem bar, Earthbind and Stoneclaw.
- Pulsing glows: expiring totems, a missing imbue, and optionally Shocks and Fire Nova when they're ready to cast. Colour, speed and size on the General page.
- Pops: a spell coming off cooldown, a totem running out, and your imbue dropping.
- Minimap button (and the minimap's addon menu): click for the options, right-click to lock or unlock positioning. The options reopen on the last page you had open.
- Earthbind and Stoneclaw show their time left as a bar only, and only the cooldown sweeps on them and on Fire Nova.
- Minor: "Pulse" is now "Fade in and out", a reworked Layout page, and fixes.

## 0.5.0 (2026-09-24)

- Totem bar (experimental): left-click drops the element's picked totem, right-click dismisses it, and the arrow tab or Alt+click picks a totem, in combat too. It can replace Blizzard's totem bars, and it's on by default.
- Timers: countdown text, swipe and time bar can each be on or off and styled (size, colour, position, time format, bar height and colour) for every cooldown and time left. Defaults on the General page, overrides on each element's page.
- Earthbind, Stoneclaw and Fire Nova can warn in their totem's last seconds.
- The Layout page has a Hidden card: drag an element there to hide it.
- Shields: charge bar height and colour.
- New defaults: larger icons, groups near the centre of the screen, 2 px borders. Profiles → Reset applies them. Countdown and timer settings from earlier versions aren't carried over.
- Fixed: logging in again sometimes switched a character back to an older profile.
- Minor: a lock/unlock button in the options footer, settings that don't apply are hidden, cleaner warning rings, and fixes.

## 0.4.1 (2026-09-24)

- Fixed: Earthbind and Stoneclaw sometimes showed a timer while a different earth totem was down.
- In positioning mode, click a group and use the arrow keys to move it (Shift: 10 at a time).
- Positioning locks when combat starts.

## 0.4.0 (2026-09-24)

- Profiles. Each character uses one, and new characters start on Default. Your current settings become the Default profile.
- Profiles can be shared as text: export one, import someone else's.
- The options window closes while positioning is unlocked and comes back when you lock. Tick Keep options open in the unlock panel to keep it open.
- Reset is now on the Profiles page and resets only the active profile.

## 0.3.2 (2026-09-23)

- Centre on screen, Split up and Hide all ask for confirmation first.
- An element's options page has an Edit group button that opens its group's settings.

## 0.3.1 (2026-09-23)

- An element can be moved to another group from its own options page.
- Minor options window improvements.

## 0.3.0 (2026-09-23)

- Shields can track Water Shield, or whichever shield is up (experimental, not yet tested in game). Lightning Shield stays the default.
- Elements with a countdown can have their own countdown text size.
- The options show a live preview of each element's looks, such as shield down or out of range.
- `/sf lock` now toggles.
- Redesigned options window.

## 0.2.1 (2026-09-23)

- Icon borders: 1 px black by default, with size, colour and on/off settings (General page), and an optional custom border per group (Layout page).
- New defaults for fresh installs (existing settings are kept): elements start in three groups, the Lightning Shield charge number is off (the charge bar shows the charges), and the Weapon Imbue icon stays hidden until the imbue is missing or running low.

## 0.2.0 (2026-09-23)

- Elements are arranged in groups, each a row or column with its own position, scale and opacity. Your current layout carries over as one group.
- Each element can show Always, In combat or Never, and each group can be set to combat only.
- New resizable options window (`/sf`). Assign elements to groups by dragging them on the Layout page.
- While unlocked: drag a group to move it, mouse wheel to scale, shift + wheel to change opacity. Optional grid and snapping.
- Slash commands trimmed to `lock`, `unlock` and `debug`; everything else is in the options window.
- New element: Weapon Imbue. Warns while no Rockbiter, Flametongue, Frostbrand or Windfury imbue is on your main hand, shows which one is, and its time left once under 5 minutes.
- Lightning Shield icon pulses while the shield is down (can be turned off).
- New cooldown elements: Earthbind Totem and Stoneclaw Totem (cooldown, plus a bar and timer while the totem is down) and Fire Nova (cooldown, greyed with a red ring while no fire totem is out).
- Beta: Blizzard's Issue Reporter button now remembers where you drag it, and can be hidden (General page).

## 0.1.4 (2026-09-22)

- Now published on CurseForge. No gameplay changes.

## 0.1.3 (2026-09-22)

- The Lightning Shield icon no longer floats above other addons' windows: it now sits in the same strata as the rest of the display.
- The Lightning Shield icon no longer reads darker than the shock icon: the no-shield underlay fades while the shield is up and Blizzard's icon alpha compensates so the two layers sum to the display opacity. New slider "No shield: combat fallback" sets how strongly the no-shield look shows if the shield drops mid-fight.
- New Lightning Shield sliders "Shielded: duration swipe" (zero turns the swipe off) and "Shielded: icon opacity".

## 0.1.2 (2026-09-22)

- Each element can be shown or hidden: "Elements" section in the options, or `/sf show|hide shield|shock`. Hidden elements keep their position and the display shrinks around them.
- Elements are laid out by their own size and centred on the cross axis, so future non-icon elements fit the row or column.

## 0.1.1 (2026-09-22)

- New display option "Only show in combat" (also `/sf combat on|off`). Off by default; the display stays visible while unlocked so it can be moved.

## 0.1.0 (2026-09-22)

First release, for the World of Warcraft: Forever beta (interface 16001).

- Lightning Shield icon with charge number and segmented charge bar, drawn by Blizzard's secure aura container so it stays exact in combat.
- Grey icon when the shield is down, plus a red ring once the state is readable again.
- Shock icon for Earth, Flame or Frost (highest known rank) with cooldown countdown, red out-of-range look, and blue not-enough-mana look with a blue ring.
- Options panel: display, layout (size, spacing, row or column, growth, icon order), shield and shock looks. `/sf` or `/shf`.
