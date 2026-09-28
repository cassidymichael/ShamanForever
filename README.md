![ShamanForever: a shaman HUD for World of Warcraft: Forever](docs/banner.png)

A configurable HUD for shamans on World of Warcraft: Forever: the buffs, imbues and cooldowns a shaman watches, as icons you can arrange anywhere. Requires WoW: Forever (interface 16001).

![ShamanForever in game](screenshot.png)

More screenshots: [options gallery](docs/gallery/README.md).

## Download

- [CurseForge](https://www.curseforge.com/wow/addons/shamanforever)
- [Wago](https://addons.wago.io/addons/shamanforever)
- [GitHub releases](https://github.com/cassidymichael/ShamanForever/releases)

## Features

Each thing the HUD shows is an element: an icon you can place in a group anywhere on screen.

### Elements

- **Shields**: Lightning Shield's charges (a segmented bar, a number, or both) and time left. While it's down the icon can go grey, get a red ring, turn red or fade in and out. It can track Water Shield, or whichever shield is up, instead (experimental).
- **Shocks**: Earth, Flame or Frost Shock's cooldown. The icon shows when your target is out of range, and when you're short of mana for the shock (or another shock you choose).
- **Weapon Imbue**: warns when your main hand has no Rockbiter, Flametongue, Frostbrand or Windfury, and shows which one is on. Its time left shows once it's low (under 5 minutes by default), and the icon can stay hidden until then.
- **Earthbind Totem and Stoneclaw Totem**: their cooldowns and their totem's time left, a warning before it ends, and a flash if it's killed early.
- **Fire Nova**: its cooldown, and a warning while no fire totem is down.
- **Tremor Totem**: "Tremor!" by the icon, with a pop, a glow and an optional sound, when a mob on its watchlist is your target or its nameplate is on screen (needs enemy nameplates). It can also warn when you're feared, charmed or asleep (off by default). It's quiet while your Tremor Totem is down, and can show the totem's time left then.
  - The watchlist starts with open-world mobs from Classic that cast fear, charm or sleep. Add mobs by name or from your target, or remove them.
  - In dungeons and raids the game hides mob names from addons, so there only the feared, charmed or asleep warning works.
- **Idle**: an element can fade or hide while there's nothing to act on, such as a spell off cooldown or a buff that isn't up. It keeps its place, and its warnings still show at full.
- **Not learned**: elements for spells your character doesn't know stay off screen, and the options mark them "Not learned".

### Experimental elements

These haven't been tested in game yet: they need spells or talents I haven't been able to try so far. The About page lists them, with a link to say how they work.

- **Nature's Swiftness**: its cooldown, and a pop and glow while it's primed, from your cast until your next Nature spell with a cast time.
- **Mana Tide Totem**: its cooldown and the totem's time left, a glow in its last seconds and a flash when it runs out.
- **Grounding Totem**: its cooldown and the totem's time left, and a flash when it ends early (it took a spell, or was destroyed).
- **Stormstrike**: its cooldown, and a bar while its effect lasts: 12 seconds from your cast, or until your next Lightning Bolt, Chain Lightning or Earth Shock. Other Nature damage on the target can use it up without the addon seeing.
- **Riptide** and **Totemic Projection**: their cooldowns.
- **Rage of the Farseer**: its cooldown, and the time left on its 25 seconds, timed from your cast.
- **Reincarnation**: its cooldown, hidden while it's ready by default. It shows your Ankh count, and warns when you're low or out, if the spell still needs an Ankh.
- **Water Walking** and **Water Breathing**: time left while up, hidden while not by default, and a warning in the last 30 seconds. The time is exact out of combat. In combat it carries on from the last reading, and casting the spell on yourself restarts it. Water Breathing can also warn when your breath bar starts to drain and it isn't up.
- **Elemental Focus**: shows while Clearcasting is up, with a pop when it procs and a glow while it lasts.

### Totem bar

- One slot per element. Left-click drops the totem you've picked for it, and right-click dismisses it. The arrow on each slot (or Alt+click) opens a picker to change the pick, in combat too.
- Each slot shows its totem's time left and warns as it runs out. You can give any totem its own warning time. If a totem is killed early, its slot flashes red and shows a cross.
- A red strip on a slot while your totem is down but you aren't getting its buff, for totems that buff you, such as Strength of Earth or Healing Stream.
- When a different totem is down, your pick can show small beside the slot.
- Call of the Elements and Totemic Recall buttons. Right-click Recall to dismiss every totem.
- Key bindings to drop each element's totem, dismiss one or all, and cast Call and Recall. Bind them by hovering the bar in Quick Keybind Mode. Each button can show its key.
- It can replace Blizzard's totem bar and active totems display, just the active totems display, or neither (the key bindings still work).
- Show it always, in combat or while a totem is down, in combat or with an enemy target, or only in combat. Drag to reorder the slots.

### Warnings and timers

- Warning looks for a missing shield, imbue or totem, or one running out: grey icon, red ring, fade in and out.
- A pulsing glow and a pop when something happens: a spell ready, a totem expiring or killed, your imbue dropping, a proc. Choose the pop's motion (grow, bounce, hop or shake), with an optional flash, ring or star burst, and the glow's colour, speed and depth.
- Timers as countdown text, a cooldown swipe, a draining bar, or any mix, each with its own size, colour, position and time format.
- Colour by time left: countdown numbers turn one colour when time is short and another at the very end, at the times you choose. They can also show tenths of a second in the last seconds.
- An optional global cooldown sweep, as on action bars.

### Layout

- Arrange elements into groups: rows or columns, each with its own position, spacing, icon size, scale, opacity and border. Drag elements between groups in the options.
- Show each element always, only in combat, or never. A group can show only in combat, or in combat and whenever you target an enemy.
- Stay after combat: a group or the totem bar shown only in combat can stay a few seconds once combat ends, then fade out.
- Positioning mode: drag groups and the totem bar, with snapping and a grid. Mouse wheel sets icon size, Ctrl+wheel scale, Shift+wheel opacity, and the arrow keys nudge. It locks itself when combat starts.
- Borders and warning rings stay pixel-sharp at any icon size.
- Test elements (`/sf test`): placeholder icons for trying out a layout, and elements you haven't learned yet, greyed.

### Options and profiles

- An options window (`/sf`, the minimap button, or Escape > Options > AddOns) with a page per element and a live preview of each look.
- Set the style once on the General page, then give any element, group or the totem bar its own where you want something different.
- Profiles: each character uses one. Make, copy, rename, delete or reset them, or share one as text.
- Spells are recognised by ID, so it should work in any game language (the options are in English).

## Usage

- `/sf` opens the options window (also the minimap button, and under Escape > Options > AddOns). Right-click the minimap button to lock or unlock positioning.
- Key bindings for the totem bar: Escape > Options > Keybindings > ShamanForever, or hover the bar in Quick Keybind Mode. Each button can show its key.
- `/sf lock` to unlock positioning and move and scale groups on screen (the bar that appears lists the controls), `/sf lock` again when done.

## Feedback

Ideas, requests or problems are welcome, any of these ways:

- A post in `#feedback` on [Discord](https://discord.gg/VaXH8CQZFG).
- A comment on [CurseForge](https://www.curseforge.com/wow/addons/shamanforever/comments).
- An [issue on GitHub](https://github.com/cassidymichael/ShamanForever/issues).

## How it works

In combat, Forever hides most of what an addon could read about auras, totems and cooldowns. ShamanForever hands that information to Blizzard's own display widgets instead of reading it, and times the few things it can't see from your own casts, which stay readable. [docs/combat-techniques.md](docs/combat-techniques.md) explains each technique.

## Development

ShamanForever is created and maintained with the help of AI tools.

- [CHANGELOG.md](CHANGELOG.md): what changed in each version.
- [docs/releasing.md](docs/releasing.md): how work reaches main, and how a release is cut.

## Art

The options banners are public-domain paintings: Thomas Moran, *The Chasm of the Colorado*; Joseph Wright of Derby, *Vesuvius from Portici*; Frederic Edwin Church, *Rainy Season in the Tropics* and *Aurora Borealis*; Francisque Millet, *Mountain Landscape with Lightning*. The corner and divider ornaments are public domain / CC0 (Wikimedia Commons). The logo is Blizzard's shaman crest, redrawn, over the same paintings and Ivan Aivazovsky's *Breaking Wave*, with a CC0 wood texture from ambientCG. The link icons on the About page are from Simple Icons (CC0). Spell icons are Blizzard's, from the game.

## Licence

MIT, see LICENSE.
