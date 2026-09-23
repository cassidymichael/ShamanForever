# ShamanForever

A configurable HUD for shamans on World of Warcraft: Forever: the buffs, imbues and cooldowns a shaman watches, as icons you can arrange anywhere.

> This addon was created by AI, with minimal oversight by a human. Feedback and requests are welcome.

![ShamanForever in game](screenshot.png)

## Features

- **Elements** for Lightning Shield, shocks, weapon imbues and totem cooldowns, each with its own look and warning settings. The Elements page in the options lists what the current version tracks.
- **Groups**: arrange elements into rows and columns, each with its own position, scale, opacity and border, or hide elements you don't use.
- **Combat aware**: show any element or group always, only in combat, or never. Everything stays accurate in combat using Blizzard's own display widgets (see [docs/combat-techniques.md](docs/combat-techniques.md)).

## Usage

- `/sf` opens the options window (also under Escape > Options > AddOns).
- `/sf unlock` to move and scale groups on screen (the bar that appears lists the controls), `/sf lock` when done.

Requires WoW: Forever (interface 16001).

> **Beta caveat, not specific to this addon:** the Forever client does not load addon settings after a full restart, so settings return to their defaults each time you start the game; `/reload` keeps them. Community workarounds such as [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix) restore them in the meantime.

## More

- [CHANGELOG.md](CHANGELOG.md): what changed in each version.
- [docs/combat-techniques.md](docs/combat-techniques.md): how auras, totems and cooldowns are shown in combat, and the one inference the addon makes.
- [docs/releasing.md](docs/releasing.md): how a release is cut.

## Licence

MIT, see LICENSE.
