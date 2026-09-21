# Changelog

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
