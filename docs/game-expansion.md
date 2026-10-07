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

These exercise the pipeline (data, tick, rendering, save, UI) with very
little new content. Summons come after, once a mana system is designed.
