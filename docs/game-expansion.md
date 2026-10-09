# Hex – Expansion Design Notes

Brainstorm notes on where the game can go. Not a spec: each section ends with
what is decided and what is still open.

## 1. The core loop

Every system should feed one loop. A system that does not connect to the
others is a menu, not a mechanic.

**Explore → gather → make → trade → get stronger → go somewhere harder**

Already in the game: overworld zones with portals and camps, NPCs, items,
weapons and spells, quests with rules, a boss, and a quick bar.

## 2. Combat: two modes, expansion targets the overworld (decided)

The game has two combat systems:

- **Overworld (zone screen):** weapons (damage, range, sneak), spells
  (`fireball`, `mend`), potions, quick bar.
- **Card battle (board):** summon cards and spell cards. Campaign, Skirmish
  and Hotseat.

**Decision:** keep the card board as it is. It is not changed, removed or
merged for now. All expansion work in this doc (statuses, quick bar,
progression, sandbox systems) targets the overworld only. Card-board
spells and units are not reused as overworld spells yet.

Revisit merging the two only if the card board starts to hold back the
overworld, or the reverse.

### Weapons vs. spells

| | Weapon | Spell |
|---|---|---|
| Cost | Free, unlimited | Mana |
| Role | Reliable default | Burst or utility |
| Identity | Range, damage, sneak | Effect, area, conjured orb or creature |

Keep both. Ideas for making weapons differ in feel, not just in numbers:

- Spear pushes the target back.
- Axe cleaves adjacent hexes.
- Dagger backstabs unaware enemies (already triples damage).
- Bow needs line of sight (already true).

Weapon upgrades stay as tokens at a campfire. Crafting becomes the way to
*get* a new weapon, not to upgrade one.

## 3. Summons (deferred, approach decided)

Not part of the first slices. When they come, they follow this approach.

Summons are spells that conjure **orbs and creatures**, not soldiers. A knight
or archer appearing from a spell reads as awkward, and a person-shaped unit
needs a walk cycle, a weapon and a reason to exist. A conjured thing is a
small sprite defined by one rule. They are also overworld-only: the card
board keeps its own summon cards.

### Starter set

| Summon | Form | Rule | Needs |
|---|---|---|---|
| Ward orb | Stationary orb | Shield aura on adjacent hexes | Shield status |
| Ember wisp | Floating flame orb | Ranged attack, applies Burn | Burn status |
| Stone sentinel | Rock creature | High HP, blocks its hex | Nothing |
| Lantern sprite | Small light creature | Lights dark zones, reveals hidden enemies | Dark-zone light |
| Thorn bloom | Plant on a hex | Roots enemies next to it | Root status (later) |

Build order: ward orb first (no AI, only an aura), then ember wisp (basic
ranged targeting). If those two work, the rest are variations.

### Rules

- A summon is a spell: costs mana, appears on a free hex near the hero.
- Objects first. Orbs and plants do one thing on a timer and never move, so
  they need no pathing. Add one moving creature (sentinel or sprite) only
  after objects work.
- Lifespan in turns, flat 3 to start, tune later. Support summons (ward orb,
  lantern sprite) can last longer.
- Cap active summons at 2.
- Show remaining turns on the sprite as a pixel number (no rings, no fades).
- Expiry is a one-frame cut, not a dissolve.
- A summon killed early refunds nothing.
- Summons act after the hero and before enemies, so outcomes are predictable.
- Summons lean on the status system (section 4), so build statuses first.

### What this needs first

- A mana pool for the hero: max, regen rule, flat cost per cast.
- Statuses (slice 1) for the wisp and ward orb.
- Persisting summon timers in `storage.dart`.

Open: mana only, or mana plus cooldown? Start with mana plus the cap.
Open: do enemies target summons, or only the hero? (Decoy-style summons
would need the former.)

## 4. Status effects

Each effect needs one rule, one icon (in `assets/pixel/sprites.txt`), one
counter, and a visible turn count.

### Starter set

| Effect | Rule | Counter |
|---|---|---|
| Burn | 1 damage at turn end, 2–3 turns. Refreshes while standing in fire. | Water hex, cleansing potion |
| Poison | 1 damage per turn. Halves healing. | Antidote, Mend |
| Stun | Skip the next turn. | Short duration, boss resistance |
| Shield | Absorbs N damage (`Unit.shield` already exists). | Expires or breaks |

### Built so far (overworld)

- Burn: enemies and the hero. 3 turns, 1 damage at turn end, refreshes.
  Fire hexes and Fireball apply it. A shield soaks it.
- Shield: spell, 2 mana, absorbs 3 damage, fades after 5 turns, can't be
  recast while full. Hero only. Resting clears all statuses.
- Bosses are special: one per zone, alone in their own spot, never near
  a portal or another boss.
- Spells come from boss fights, one per zone. The cave Pyromancer teaches
  Fireball. The Warlord teaches Shield. Its blast hits harder (3 centre,
  2 ring) and leaves no fire. It is planned for its own zone beyond the
  Hollow Deep (section 10), so Shield cannot be learned yet.

### Second wave

Slow (less movement), Root (cannot move, can act), Weaken (less damage),
Haste (extra move), Bleed (damage when moving), Mark (next hit does more),
Regen (heal per turn).

### Boss / rare

Fear, Charm, Freeze. Keep these out of the early game.

### Interactions (what makes it feel like a sandbox)

- Fire + forest: already works. Burn is the same system.
- Water extinguishes burn. A wet unit takes extra lightning damage.
- Stun + sneak: a stunned enemy counts as unaware, so the dagger triples.
- Lava applies burn on entry. Crystal could amplify spells.
- Mud or ice applies slow.
- Gust pushes units into water, lava or traps.

### Rules to keep it readable

- One status per type at a time. Reapplying refreshes, it does not stack.
- Short durations, 2–3 turns.
- Bosses resist, via a per-boss immunity list in `boss.dart`.
- Turn-end order: apply damage, tick durations, remove expired.
- Always show when a status is applied (marker or combat log line).
- Every effect has something that applies it and something that clears it.

Open: enemy-only first, then the hero once a counter exists? Does poison
halve healing or block it entirely (blocking is harsh early on)?

### Implementation notes

- Add `Map<Status, int> statuses` to `Unit`, `Enemy` and the hero in
  `world_state`. Add a `StatusDef` table next to `itemDefs` and `spellDefs`.
- `ZoneSim.tick()` already calls `_fireStep()`. Add `_statusStep()` beside it,
  and have fire apply the burn status so there is one burn rule, not two.
- Persist hero statuses and summon timers in `storage.dart`.
- Enemy AI: stunned skips, slowed moves less, rooted does not path.
- Status rules are deterministic, so they are easy to unit test.

## 5. Quick bar (decided)

Currently three groups (weapons, spells, potions) in a `Wrap`, each slot
tap-to-use.

- **Swipe selects, tap uses** (decided). A swipe anywhere on the screen
  moves one slot, not only on the bar.
- Bigger slots than the inventory slots.
- The selected slot is larger, snapped to whole device pixels, and slightly
  raised. No bounce or spring.
- One strip, ordered weapons → spells → potions, with a thin divider
  between groups.
- Horizontal swipe anywhere on the screen moves one slot. A fast fling
  jumps a group.
- Tap on the selected slot uses it. This avoids accidental casts.
- The swipe must not fight tap-to-move or camera drag: use a minimum
  distance and a horizontal axis lock, and tap-to-move only fires on a
  tap, never at the end of a swipe.
- Show about five slots with the selected one centred. With few slots,
  do not scroll.
- Keep a tap-only path so swipe is a shortcut, not a requirement.

Decided for now: a swipe while aiming moves the selection and ends the aim
(only Fireball is aimed today). Revisit when a second aimed spell exists.
Open: exact swipe threshold and axis lock (needs a device test).

## 6. Progression and pacing (decided approach)

New systems arrive one at a time. A system is not introduced until the
previous one has been used.

- Unlock by doing, not by timer.
- One new tool per zone or per boss.
- Each lesson ends with a small proof step ("kill this enemy with a spell").
- Hide anything not unlocked. `QuickBar` already hides empty groups, so use
  the same rule for menus and tabs.

### Suggested unlock order

1. Weapons and sneaking (meadow, training zone).
2. Fireball, which introduces burn.
3. Mend and Shield.
4. First summon (ward orb), once mana exists. Deferred for now.
5. Poison from a cave enemy, with the antidote as the first crafted item.
6. Stun, via a boss mechanic.
7. More summons (ember wisp, then creatures). Deferred for now.
8. Scavenging and resource nodes.
9. Crafting at the camp.
10. Currency and a trader.
11. Side quests that use those systems.
12. Skill tree.
13. Camp building and farming (heaviest, last).
14. Slow, root, mark in later zones.

## 7. Sandbox systems

Brought in gradually per section 6. Short version:

- **Scavenging:** resource nodes tied to terrain (ore in caves, herbs and wood
  in the meadow, crystal near crystal tiles), hidden stashes, enemy drops.
- **Crafting:** recipes from NPCs and scrolls, stations at camps. Makes
  potions, weapons, spell cards, ammo and later structures.
- **Skill tree:** changes how you play (hand or slot count, cheaper first
  summon, summon placement) instead of flat percentage nodes.
- **Camp building:** a small buildable hex plot with adjacency bonuses.
- **Farming:** three or four crops, grown per fight or zone change.
- **Economy:** one currency, zone-varying prices, wandering traders. Sinks
  matter more than sources: repairs, upgrades, rare recipes, portal fees.
- **Quests:** main story gates zones, side quests use the new systems,
  discoveries have no marker.
- **Reputation:** NPC standing unlocks recipes, discounts and quests.

Other ideas: day and night (the meadow already has a `dark` flag),
companions, weather and hazards, a bestiary and recipe journal, an endless
challenge mode.

## 8. Cautions

- **Scope.** Each system is a game on its own. Prefer thin versions of all
  over deep versions of two.
- **UI load.** CLAUDE.md requires one primary action per screen and the pixel
  kit. Crafting, trading and building screens must reuse `Panel` and
  `Choice`, not grow dense grids.
- **Balance.** Keep numbers in data files, not code.
- **Saves.** Design the save format for statuses, summons, crafting,
  buildings and farming once, with a version number.

## 9. First slices to build

1. Burn as a status on the existing fire system, plus the status icon and
   turn counter UI. Enemy-only first.
2. Quick bar rewrite: bigger slots, larger selected slot, swipe to select,
   tap to use.

3. Broken bridge, wood and the hatchet (section 10): the `broken` tile, wood
   as a stackable material, chopping a forest tile, repairing a bridge.

These exercise the pipeline (data, tick, rendering, save, UI) with very
little new content. Summons come after, once a mana system is designed.

## 10. World, quests and locks (draft)

Zones and quests come before more spells or weapons. A zone should make sense
on its own and give a reason to go back. Bosses are special: one per zone,
alone in their own spot (section 4), and each teaches a spell.

### Lock and key rules

- A lock is visible before you can open it. You see the broken bridge, the
  far bank, something worth reaching, and the game says nothing.
- The key is somewhere else, in another zone. The quest ties them together.
- A lock never blocks the main path. It guards a shortcut, a side reward or a
  boss. The main story must stay playable without it.
- One lock type per new tool, so each tool opens something new.
- Locks are persistent: a repaired bridge stays repaired across rests and
  saves.

### Zone map (existing and planned)

The Whispering Meadow is split into a left and a right side by a river. There
is one bridge, and it starts broken. The Old Mine and the Hollow Deep are
sub-zones of the meadow: separate maps entered by portal from it. The
Quarry (the Warlord's zone) is a separate map outside the meadow region.

```
Training Ground -> MEADOW LEFT ~~ 1 broken bridge ~~ MEADOW RIGHT
                   |                                   |
                   Old Mine (top-left)                 Hollow Deep
                   hatchet                             lantern, Pyromancer,
                                                       |
                                                       rockfall + charge
                                                       (needs Fireball)
                                                       |
                                                       Quarry (Shield)
```

| Zone | State | Contains |
|---|---|---|
| Training Ground | Exists | Tobin, sword, bow, Mend lesson. Gate until training is done. |
| Meadow, left side | Exists | Arrival from training. Camp, Mara, forests (wood). Only knights. The river blocks the way east. Entrance to the Old Mine in the top-left. |
| Old Mine | New sub-zone | Dark. A few enemies and the hatchet. No boss. |
| Meadow, right side | Exists | Reached by repairing a bridge. A mix of archers and knights. More forests. Portal to the Hollow Deep. |
| Hollow Deep | Exists, to rebuild | A dungeon of four rooms (section 11): the lantern first, then the rockfall and its charge, then the Pyromancer (Fireball) by another route. Blasting the rockfall opens the way on. |
| Quarry | New, separate map | Reached through the rockfall. The Warlord, alone, at the far end (Shield). It is the last zone of the Marches (section 12). |

The order is forced by the world and not by a gate message. You cannot reach
the Hollow Deep until you have the hatchet from the Old Mine, wood from the
left side, and a repaired bridge. You cannot reach the Warlord until you
have Fireball from the Pyromancer and blasted the rockfall.

The meadow has one river, a single gentle meander with a changing width and
no second channel. It crosses the whole map, so the bridge is the only way
over. The bridge sits at a narrow point. The cave portal is on the right
side.

### Enemies by area (for now)

Only archers and knights while the systems are young. Cavalry and golems come
later, in new zones.

| Area | Enemies |
|---|---|
| Meadow, left | Knights only |
| Meadow, right | A mix of archers and knights |
| Old Mine | Knights and archers, few |
| Hollow Deep | As built (golem and Pyromancer stay) |

### Quest: Mara's lantern, extended

The lantern is in the Hollow Deep, which is across the river, so the quest
forces the whole chain.

1. Mara asks you to find her lantern in the Hollow Deep, across the river.
   You see the broken bridge.
2. She mentions that her late husband's hatchet is in the old mine, in the
   top-left, and that he used it to repair the bridge.
3. In the Old Mine you find the hatchet.
4. Back in the meadow you chop trees for wood, then repair a bridge.
5. You cross, work through the Hollow Deep dungeon, and find the lantern.
   The rockfall and its charge are further in, for the next goal.
6. You bring the lantern back to Mara.

Mara mentions the bridge and the hatchet when asked, or when you first see a
broken bridge. The quest log shows only the next step.

### Chopping and repairing

- Chop: stand next to a forest tile with the hatchet and act on it. It drops
  1 to 3 wood, by how well you do in the timing strike. The tile becomes grass, so forests deplete
  and fire and chopping compete for the same trees.
- A small timing strike (see "Built so far"), always skippable with a quick
  chop for 1 wood.
- Repair: stand next to a broken bridge with 30 wood and act on it. The tile
  becomes a ford.
- At an average of 2 wood a tree, that is about 15 trees. 30 wood is three
  bag slots (stack of 10).
- Both rules reuse the session zone copy that fire already uses. The set of
  repaired bridges is saved in `WorldState` (like `slain` and `collected`).
- The rockfall is not opened with a tool. See section 11: a charge and
  Fireball.

### Inventory: slots are the weight

No separate weight number. Each item has a stack size, which is how many fit
in one slot. Bulky things get small stacks, so carrying them costs space.
11 wood with a stack of 10 is two slots, 10 and 1. This is how `addItem` already
works.

| Item | Stack |
|---|---|
| Weapons, tools (hatchet) | 1 |
| Potions | 5 |
| Wood | 10 |
| Ore or stone (later) | 3 |

- The 16-slot bag is the only limit. "Bag full" is the "too heavy" message.
- Wood is a new item kind, `material`. Tools stay in the bag, never used up.
- Quest items stay in the bag and cannot be dropped (this is how `drop`
  already works).
- A bigger pack (a quest or boss reward) raises the slot count later.

### Other locks, for later

| Lock | Key | Notes |
|---|---|---|
| Broken bridge | Wood (hatchet to cut it) | Built first. |
| Rockfall | Fireball, lit on a charge beside it | Section 11. |
| Dark passage | Lantern | The cave is already dark. |
| Locked gate | A key found in a zone | Plain and clear. |
| Frozen river | Fire | A later zone. |

### Built so far (meadow slice)

- The meadow has one river and one broken bridge. It must be mended to reach
  the right side and the Hollow Deep. The old fords are plain water. No lava
  in the meadow: it belongs in the cave.
- Tile `b` is a broken bridge. A bridge is a connected run of `b` tiles;
  mending turns the whole run into a ford. Mended bridges and felled trees
  are saved (`repaired`, `chopped`, save version 2).
- Items: `wood` (material, stack 10) and `hatchet` (tool). Tools
  and quest items cannot be dropped.
- A button above the quick bar shows the one thing you can do where you
  stand: "Chop tree" next to a tree with the hatchet, or "Mend bridge n/5
  wood" next to a broken bridge. Chopping gives 1 to 3 wood and leaves grass.
- Old Mine (`mine.txt`): dark sub-zone off the top-left of the meadow, with
  the hatchet at the far end, a sleeping knight and an archer.
- Mara points you to the Old Mine, then the trees, then the cave. The quest
  log follows the same order.
- Meadow enemies: knights only on the left, archers and knights on the right.

- Chopping is a timing strike: tapping "Chop tree" opens a panel with a
  marker stepping along a bar, and you tap Strike while it is over the gold
  cells. Three swings, each hit is one wood, a tree always gives at least
  one. "Quick chop" skips it for 1 wood. It is not available while an enemy
  is hostile ("Not now"), and a miss never hurts you. A better tool could
  widen the gold later.

Not built yet: the Hollow Deep dungeon, the rockfall and charge, the
Quarry.

### Decided

- One tool, the hatchet (wood). The rockfall is opened by Fireball, not a
  tool. A pickaxe may return later for ore nodes in the Quarry.
- One bridge, broken at the start, 30 wood to mend. (Two parallel channels
  looked artificial, so the second bridge was dropped.)
- A forest tile drops 1 to 3 wood, random.
- The Hollow Deep becomes a four-room dungeon (section 11). The lantern
  comes first, the Pyromancer is reached by another route.
- The Quarry is the Warlord's zone and ends the Marches. The city comes
  after it (section 12).
- Focus is on the Whispering Meadow first.

### Open questions

1. The room layout of the Hollow Deep (section 11), drawn as a map.
2. Look of the Quarry.
3. Does a damaged bridge show how many wood it still needs (a counter on the
   tile), or only at the moment you act? Today only the button shows it.
4. Tuning the timing strike on a phone: step speed and the width of the gold.

## 11. The Hollow Deep (draft)

Today the cave is one open cavern, and the lantern sits two tiles from the
Pyromancer. It becomes a dungeon of four rooms. The player sees the lock
before they hold the key, and the boss is never met by accident.

```
Entrance (camp)
   |
 Room A: first fights, potion, longbow
   |
 Room B: the lantern (on the main route, no boss)
   |
 Hub J: a wide hall where the routes split
   |-- south: Room C, the rockfall and the charge (dead end for now)
   |-- north: Room D, the Pyromancer (Fireball)
   |
 back to Room C: light the charge, the rubble opens -> Quarry
```

### Order of play

1. The lantern comes first and sits on the main route. Picking it up lets
   the player finish Mara's quest.
2. Room C shows a blocked exit and an inert charge. Weapons and arrows do
   nothing to it, so the player knows the answer is elsewhere.
3. The route to the Pyromancer branches away from Room C. The player has to
   turn back to take it, so the boss is not met by accident. The golem and
   the archer guard that route.
4. Fireball ends the fight and opens the way. The player backtracks through a
   cleared dungeon, lights the charge from a safe distance and the rubble
   clears.

### Charge and rockfall rules

- The charge has its own sprite (a crate of powder with a fuse), so it does
  not read as a barrel. Seeing it is the hint. Nobody tells the player.
- Only the hero's Fireball, or a hex it set burning, detonates it. Weapons,
  arrows, knights and the Pyromancer's fire do not. Enemy fire could set it
  off as a trap in a later zone.
- The blast radius is smaller than Fireball's range, so the player can light
  it from a safe distance. Standing in the blast hurts the hero.
- The blast turns the rubble into floor, once. A `blasted` set in
  `WorldState`, like `repaired` and `chopped`, keeps it across rests and
  saves. That needs a save version bump.
- Keep Room D far from Room C so the Pyromancer's fire cannot reach the
  charge.

### Charge and rockfall, as built

- Zone file tiles: `X` is rubble, `T` is a charge. Neither is walkable. Rubble
  is a mountain tile with a `rubble` flag, so it blocks sight too. A charge is
  a floor tile with a `charge` flag. Both draw a sprite over the tile
  (`rubble`, `charge` in `sprites.txt`).
- Only the hero's Fireball sets a charge off: if the charge is the target or
  in its ring of six. Weapons, and boss fire, never do.
- The blast hurts everything on the charge's hex and the six around it for 3
  (`ZoneSim.chargeDamage`), the hero included, and shield soaks it. Fireball
  range is 4, so standing 3 or 4 hexes away is safe.
- It clears every run of rubble with a hex within 2 of the charge
  (`chargeReach`). The charge hex becomes floor.
- A `blasted` set in `WorldState` (`zone#q,r` of the charge) keeps it open
  across rests and saves. The save version is 4.
- A `blasted` event drives a shake, a burst and "Rockfall cleared".

Hints for the player (built):

- Tapping the crate shows "Blasting powder. Fire sets it off." It says what
  it is and nothing about Fireball.
- The crate has a flame mark on its front, so it reads as explosive.
- The survey scroll in Room C says the Watch left powder by the rubble and
  that nobody would put a flame near it.
- Tobin's last training line gives the quest "Reopen the road". Its log entry
  says "Find a way past the rockfall in the Hollow Deep" and, only once
  Fireball is known, "Light the powder by the rockfall with Fireball." It
  finishes when the charge goes off (`Quest.finishedWhen`). The Mara quest
  keeps priority for the map marker while it is active.

Not done yet: the Quarry portal behind the rubble.

### Mara's quest and the log

Mara's objective ends with the lantern. A second quest, from Tobin, covers the
road: "Reopen the road" (reach the rockfall, learn Fireball, blast it). It is
built. The quest log shows only the next step, as before.

### The dark

The cave is dark. The lantern is Mara's and stays a quest item: it does not
grow the light radius, because handing it over would take that away. If the
dungeon needs more light, that is a separate item, a miner's lamp found
deeper in, that the player keeps.

### Built layout

`assets/zones/cave.txt` is built (33 by 22, columns by rows, odd-r):

- Room A, entrance cavern (bottom left): camp and the longbow. No enemy
  waits here. Portal at col 3, row 19.
- Room B, lantern room (left): lantern at (8,9), a small pool, a patrolling
  knight, a potion. It is the only way on from A.
- Hub J (centre): crystals and a lava patch in the middle, an archer on guard,
  a potion. The routes split here.
- Room C, dead end (bottom right): reached by a corridor south of the hub.
  The east end (col 25, rows 18 to 19) is where the rockfall and the charge
  go. Holds an ether potion.
- Room D, Pyromancer (top): reached by a corridor north of the hub past a
  sleeping golem. The War Axe is in an alcove off that corridor. The boss is
  at (20,2), 25 hexes from the entrance and 17 or more from Room C.

The rockfall and charge are built (see "Charge and rockfall, as built"). The
map is 33 columns wide: Room C's east end holds the charge (col 25, row 18) and
two hexes of rubble (col 26, rows 18 and 19). Behind them is a short corridor
(cols 27 to 31) that ends in nothing until the Quarry portal exists.

### Open questions

1. Does the Pyromancer fight stay "alone in his own spot" (section 4) when
   the golem and archer guard the route to him? The layout assumes yes: only
   the golem is on that route, and it sleeps.
2. Where the rockfall tile and the charge go in Room C, once they exist.

## 12. World and lore (draft)

The Marches are the first of six regions. A city sits where six old roads
meet. The player reaches it only after the Marches.

### Lore

The city kept six roads open, with a warden on each. The wardens stopped
reporting and the council shut the gates from the city side. The Watch still
sends recruits to the nearest road to learn the work. That is Tobin's
Training Ground. The player is one of those recruits.

| Place | In the story |
|---|---|
| Training Ground | The Watch's outpost on the south road. |
| Meadow | Abandoned holdings along that road. Mara's husband was a woodcutter who went to mend the bridge and did not return. |
| Old Mine, Hollow Deep | The holding's mine and the cave the south warden's road ran through. |
| Rockfall | What shut the south road. Reopening it is the recruit's real task. |
| Quarry | Where the south warden ended up. The Warlord holds it. |

### The Marches (region 1)

```
Training -> Meadow L -> Old Mine -> Meadow R -> Hollow Deep -> Quarry
```

The chain teaches one new thing per zone before any open map:

| Zone | Teaches |
|---|---|
| Training | Move, sneak, weapons, Mend |
| Meadow left | Explore, the broken bridge |
| Old Mine | Dark zones, the hatchet |
| Meadow right | Wood and the bridge, ranged enemies |
| Hollow Deep | Dungeon rooms, the lantern, Fireball |
| Quarry | Using Fireball on the world; Shield from the Warlord |

### The city (later)

After the Quarry the road opens onto the city, called Sixways for now. It
is a neutral hub: no fighting, no enemies, enforced by a `safe` flag in the
zone file. Shops, quest givers and minigames are NPC stalls around a central
square, in one map. The card board is played at an arena table, which links
the two combat systems.

Six gates lead out, one per region. Gate one is the road the player came by.
The others open by proof: a boss reward carried back to the city, using the
existing `Gate` and `closedGate` code. Three regions get planned first and
the rest stay sealed with a line of lore. Each region maps to a lock in
section 10: a frozen river (fire), a marsh (poison, antidote) and a
quarry-like region for ore.

### Open questions

1. Name of the city and of each region.
2. Which three regions come first.
3. Where the city's `safe` flag lives and what it switches off in `ZoneSim`.

## 13. Lore pickups (draft)

Scrolls the player finds and reads. They tell the story of the world without
dialogue, and each one should be about the place it lies in.

### Rules (built)

- A scroll is an item of kind `lore`, placed with a normal `item` line in the
  zone file. Its text lives in `lib/world/lore.dart` (`loreDefs`), keyed by
  the item id.
- Walking onto it reads it at once, in a panel, and files it in the journal
  (`WorldState.scrolls`, saved from version 3). It never takes a bag slot, so
  a full bag does not stop it.
- The journal lists every scroll found, in the order found. Tap one to read it
  again. The list is hidden until the first scroll.
- Scrolls are 2 to 3 short lines, plain. One idea each.
- Scrolls are optional. Nothing is locked behind reading them.
- Pickups are saved in `collected` like other items, so a scroll is read once
  and not offered again.

### First scrolls

| Place | What it tells |
|---|---|
| Training Ground, `scroll_orders` | Why Tobin is there: the Watch holds this post and trains recruits for the south road. Built, next to Tobin. |
| Hollow Deep Room C, `scroll_survey` | How the rock blocked the route: the roof came down, the warden's crew was on the far side. Built, in Room C. |
| Hollow Deep Room B, `scroll_woodcutter` | A note from Mara's husband about the bridge and the groaning ground. Built, near the lantern. |

### Open

1. A distinct sprite per scroll type. All three use one `scroll` sprite today.
2. Whether the journal gets its own screen once there are many scrolls.
