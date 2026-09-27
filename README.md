![ShamanForever: a shaman HUD for World of Warcraft: Forever](docs/banner.png)

A configurable HUD for shamans on World of Warcraft: Forever: the buffs, imbues and cooldowns a shaman watches, as icons you can arrange anywhere. Requires WoW: Forever (interface 16001).

![ShamanForever in game](screenshot.png)

More screenshots: [options gallery](docs/gallery/README.md).

## Download

- [CurseForge](https://www.curseforge.com/wow/addons/shamanforever)
- [Wago](https://addons.wago.io/addons/shamanforever)
- [GitHub releases](https://github.com/cassidymichael/ShamanForever/releases)

## Features

### What it tracks

- **Lightning Shield**: charges as a segmented bar, a number, or both, and time left. When the shield is down the icon can go grey, get a red ring, turn red or fade in and out. It can track Water Shield, or whichever shield is up, instead (experimental).
- **Shock**: Earth, Flame or Frost Shock's cooldown. The icon shows when your target is out of range, and when you're short of mana for the shock (or another shock you choose).
- **Weapon Imbue**: warns when your main hand has no Rockbiter, Flametongue, Frostbrand or Windfury, shows which one is on, and its time left once it's under 5 minutes. It can stay hidden until the imbue is low or gone.
- **Earthbind Totem, Stoneclaw Totem and Fire Nova**: their cooldowns. Earthbind and Stoneclaw also show how long their totem has left, warn before it ends and flash if it's killed early. Fire Nova shows when no fire totem is down.
- **Idle**: cooldown elements can fade, or hide, while there's nothing to act on. They keep their place, and their warnings still show at full.

### Totem bar

- One slot per element. Left-click drops the totem you've picked for it, right-click dismisses it, and the arrow on each slot opens a picker to change the pick, in combat too.
- Each slot shows its totem's time left, warns as it runs out, and flashes red with a cross if the totem is killed early.
- A red strip on a slot when your totem is down but you aren't getting its buff, for totems that buff you, such as Strength of Earth or Healing Stream.
- Call of the Elements and Totemic Recall buttons. Right-click Recall to dismiss every totem at once.
- Key bindings to drop each element's totem, dismiss one or all, Call and Recall. Bind them by hovering the bar in Quick Keybind Mode; each button can show its key.
- It can replace Blizzard's active totems display, both of Blizzard's totem bars, or neither.
- Drag to reorder the slots, and give any totem its own warning time.

### Warnings and timers

- Warning looks for anything missing or running out: grey icon, red ring, fade in and out.
- A pulsing glow and a pop for the moments that matter: a spell ready, a totem expiring or killed, your imbue dropping. Choose the pop's motion (grow, bounce, hop or shake), with an optional flash, ring or star burst, and the glow's colour, speed and depth.
- Timers as countdown text, a cooldown swipe, a draining bar, or any mix, each with its own size, colour, position and time format.
- An optional global cooldown sweep, as on action bars.

### Layout

- Arrange elements into groups: rows or columns, each with its own position, icon size, scale, opacity and border. Drag elements between groups in the options, or hide ones you don't use.
- Show each element or group always, only in combat, or never.
- Positioning mode: drag groups and the totem bar, with snapping and a grid. Mouse wheel sets icon size, Ctrl+wheel scale, Shift+wheel opacity, and the arrow keys nudge. It locks itself when combat starts.
- Borders and warning rings stay pixel-sharp at any icon size.

### Options and profiles

- An options window (`/sf`, the minimap button, or Escape > Options > AddOns) with a page per element and a live preview of each look.
- Set the style once on the General page, then give any element, group or the totem bar its own where you want something different.
- Profiles per character: copy, reset, or share one as text with other players.
- Spells are recognised by ID, so it should work in any game language (the options are in English).
- Features that haven't been tested in game yet are labelled experimental, with a link to report how they work.

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

In combat, Forever hides most of what an addon could read about auras, totems and cooldowns. ShamanForever stays accurate by handing that information to Blizzard's own display widgets instead of reading it. [docs/combat-techniques.md](docs/combat-techniques.md) explains each technique.

## Development

ShamanForever is created and maintained with the help of AI tools.

- [CHANGELOG.md](CHANGELOG.md): what changed in each version.
- [docs/releasing.md](docs/releasing.md): how work reaches main, and how a release is cut.

## Art

The options banners are public-domain paintings: Thomas Moran, *The Chasm of the Colorado*; Joseph Wright of Derby, *Vesuvius from Portici*; Frederic Edwin Church, *Rainy Season in the Tropics* and *Aurora Borealis*; Francisque Millet, *Mountain Landscape with Lightning*. The corner and divider ornaments are public domain / CC0 (Wikimedia Commons). The logo is Blizzard's shaman crest, redrawn, over the same paintings and Ivan Aivazovsky's *Breaking Wave*, with a CC0 wood texture from ambientCG. The link icons on the About page are from Simple Icons (CC0). Spell icons are Blizzard's, from the game.

## Licence

MIT, see LICENSE.
