# Combat techniques

Why ShamanForever behaves as it does in combat. On WoW: Forever, addon code can't read most combat data (Blizzard's "secret values"). ShamanForever never does math or comparisons on a value that may be secret. Where it can't read something, it hands Blizzard's own objects to Blizzard's own widgets, which draw them exactly; where even that isn't possible, it times things from your own casts, which stay readable.

In a PvP match, Blizzard's API documentation says auras, cooldowns and totem slots stay secret out of combat too, until the match ends (not yet tested in a battleground). So wherever this page says "in combat", a match counts as combat from start to end. The totem bar's buttons and layout still change between fights: only combat locks them.

## What can be read in combat

| | In combat |
|---|---|
| Auras (buffs and debuffs, yours included) | No. Blizzard's aura display can show them, but addon code can't read them or learn when they end. |
| Cooldowns and totem timers | Not as numbers, but Blizzard's timer widgets draw them exactly. |
| Which totem is in a slot | No. The addon knows it from your own cast. |
| Your own casts | Yes. |
| Weapon imbues | Yes. |
| Reagent counts | Yes. |
| Your breath bar | Yes. |
| Loss of control on you | Yes. |

## Shields

Blizzard's own aura display draws the shield: its icon, charges and time left, exact in combat. Under it sits ShamanForever's "no shield" look (grey icon, red ring, pulse). Nothing tells an addon in combat that the shield has dropped, so the look follows what the addon believes:

- **Out of combat** it is exact, read from the aura.
- **In combat** your own successful cast of a tracked shield means it is up. Only one elemental shield can be on you at a time, so casting one you don't track means yours is down. That is the one inference.
- **Nothing can say "down" in combat.** If the shield drops mid-fight, the no-shield look shows at the "In-combat fallback" strength until you recast it or combat ends.
- **After a login or `/reload` in combat,** nothing is known until your next cast or the end of combat, and nothing warns.

The look under Blizzard's icon only matters when the group's opacity is below 100%, which makes Blizzard's icon see-through. At 100% it is covered completely.

## Timers and warnings

Cooldowns and totem timers are drawn by Blizzard's timer widgets from what the game hands over, so they are exact without the addon reading them. Warnings that depend on something secret (Fire Nova with no fire totem down, a totem about to expire, a ready glow) are passed to the game to show or hide, never decided by addon code.

**Which totem is yours:** the one you last cast into that slot. Call of the Elements counts as a cast of each totem it drops. After a `/reload` in combat with a totem already out, its timer stays hidden until it ends or you recast it.

## Timed from your own casts

Some effects can't be read in combat at all, so they are timed from your cast, and corrected from the aura whenever auras are readable:

- **Nature's Swiftness:** from its cast until your next Nature spell with a cast time.
- **Stormstrike:** 12 seconds from the cast, or until your next Lightning Bolt, Chain Lightning or Earth Shock. Other Nature damage on the target may use it up unseen.
- **Rage of the Farseer:** its 25 seconds from the cast.
- **Water Walking and Water Breathing:** exact out of combat. In combat the time carries on from the last reading, and your own cast restarts it when there's no other friendly target (they can be cast on others). A buff cancelled or dispelled in combat is seen when combat ends.

## The totem bar in combat

- **Clicks work in combat:** every button (cast, dismiss, open and close a picker, pick a totem) is set up as a secure button out of combat.
- **Layout** (showing, hiding and moving buttons) only changes out of combat; changes made in combat wait for it to end.
- **Out of range:** no addon can measure the distance to a totem. The strip shows whether you have your totem's buff, drawn by Blizzard's aura display. A buff lingers a few seconds after you leave range, and another shaman's same totem can replace yours. After a `/reload` in combat the strip waits until combat ends.
- **Killed early or ran out:** told apart by the time the totem had left when its slot emptied. Your own dismissals, Totemic Recall included, count as neither.
