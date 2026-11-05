# Hex Diner — Game Engine Reference

Technical reference for every game system: how the numbers work, what is well-designed, what is broken or unbalanced. Written for the developer.

---

## 1. Menu & Dish

**How it works.** `Diner.menu()` maintains an `offered` list that auto-fills up to `menuSlots = 1 + (level+1)÷2` dishes from `Dish.values` enum order, skipping anything in `declined` or not `available`. It mutates `offered` as a side effect on every call.

Per dish the player controls: **Tier** (Budget/Standard/Premium), **markup** (−30% to +60% in 10% steps), and one **Special** (20% off, +10% crowd, boosted order frequency).

```
sellPrice(d) = progress.price(d) × priceRatio(d)
progress.price(d) = recipe.price × (1 + 0.25 × (recipeLevel − 1))
```
Level 5 recipe → 2× base price.

```
unitCost(d) = recipe.price × tier.costFrac × today.costMul × supplier.costMul
```

Ingredient cost is a fixed fraction of **base price**, not sell price. At Standard (`costFrac=0.26`), a Burger (base 8) always costs ~2.1 regardless of markup or recipe level. Recipe levelling is therefore highly leveraged: price grows 25%/level, cost stays fixed.

**Good.** Wallet × markup × tier creates a genuine three-way tradeoff. Thrifty tolerance is 1.0×; Standard tier with any markup > 0 starts excluding them. This is non-trivial reasoning the player must do.

**Issues.**
- `menu()` mutates `offered` as a side effect every call, including inside `report()` and `forecastPlan()`. Non-deterministic if called in unexpected order during the same frame.
- `declined` dishes cannot be reinstated through any obvious UI path. `toggleOffer` requires the dish to be absent from `offered`, but declined dishes are excluded from auto-fill and don't appear in the menu list.
- Recipe levelling returns ~2× sell price at max level for 400 coins total. That is the best ROI in the game by a large margin and is not surfaced anywhere.
- The special's expected value is almost always positive (10% crowd lift typically beats 20% cut), but the UI shows no break-even calculation.

---

## 2. Staff

**How it works.** Each `Staff` has: `salary` (fixed), `morale` (0–10), `grudge` (0–3), `mastery` per dish/machine, `station` assignment, and hidden `traits`.

At settlement, `applySettlement()` processes `Map<int, bool> paid`:
- **Paid**: `morale = min(morale+1, 10)`, `grudge = 0`.
- **Skipped**: `morale -= 2`; if `hotHeaded` another `−2`; if `morale ≤ 0` → `quit = true`, removed from roster immediately.
- **Loyal-but-skipped**: `grudge++`; morale only drains when `grudge == 3`.

`willQuitIfUnpaid = morale − 2 ≤ 0` (or `−4` for hotHeaded).

Morale now affects cook/walk pace during service: `paceMul *= 0.9 + 0.01 × morale` — full speed at morale 10, 90% at morale 0.

**Good.** Deferring wages to settlement creates a nightly resource decision with real stakes. The `willQuitIfUnpaid` warning gives just enough information without over-explaining the trait system.

**Issues.**
- Skipping wages is strictly better than firing early: a 5-morale hire can be skipped 2–3 days for free labour. No reputation or guest-experience penalty beyond morale loss.
- `grudge` is never shown to the player. Loyal staff appear identical until they quit after 3 skips with no visible warning path.
- `Staff.quit` is a transient flag not serialized. If the app restarts between `applySettlement()` and `_save()`, the quit staff reappears. In practice `_save` runs immediately after in `_onSettlementConfirm`, so this is safe — but the flag is redundant since roster removal already happened.
- `trainedToday` resets in `finishDay()`, not `applySettlement()`. Correct per current flow but fragile if the two are ever called out of sequence.

---

## 3. Supplier

**How it works.** Three options: `market` (0.8× cost, spoilage), `standard` (1.0×), `farm` (1.25× cost, 1.1× tips, unlocks level 3).

Spoilage is deterministic per day: `market` rolls `Random(day×6151+29).nextDouble() < 0.2` → bad day (35% spoiled) or normal (10% spoiled). Seed is fixed, so the schedule is known.

Supplier gates ingredient tier via `supplierMaxTier`: market→Budget only, standard→Standard max, farm→Premium max. `tierOf(d)` silently caps downward.

**Good.** The supplier–tier coupling creates a meaningful nightly decision. Can't min-max cheaply since market loses tier access and rep takes a hit from Budget dishes (−6 rep/dish vs 0 for Standard).

**Issues.**
- Market is dominated at almost every level. 20% cost saving is consumed by Budget's −6 rep/dish penalty and spoilage waste. Standard is strictly better unless the player is cash-negative at day start, and even then there are better options (fewer portions, skip wages).
- Farm's 1.1× tip bonus is applied in the sim, not shown in `DishScreen` profit preview. The break-even analysis the UI shows ignores this uplift.
- Tier downgrade on supplier switch is silent. Switching Farm→Standard at settlement quietly drops all Premium dishes to Standard next morning — settlement screen now warns which dishes will be capped.
- `supply` upgrade (90×1, 90×2, 90×3 = 540 total) reduces market spoilage but becomes worthless the moment the player uses Standard or Farm.

---

## 4. Service Simulation

**How it works.** Day = 300 ticks (120s at 0.4s/tick) + 150-tick last-call wind-down. Each tick: advance actors, process machines, spawn guests, run staff AI, process guest states.

Guests carry `Wallet` (thrifty/regular/wealthy), `Temper` (hasty/steady/easygoing). At arrival they roll orders from menu, filtered by `Wallet.tolerance` vs `priceRatio`. Nothing within budget → they leave immediately (no sale, no rep feedback for this case).

Tip formula: `guestWallet.tipMul × supplier.tipMul × decor.tipAt(seat) × regular.tipMul`.

Cook time: `base × (1 − 0.08×kitchenUpgrade) × (1 − 0.06×(recipeLevel−1))`, clamped 2–99 ticks.

**Good.** Staff AI, pathfinding, and station-assignment modelling are architecturally solid. The pass hatch correctly separates kitchen/front-of-house workflows.

**Issues.**
- Staff with no station assignment race for the same machine. Two staff can deadlock on a single grill while another is idle. `uncoveredMachines` is computed but its warning is not prominently surfaced.
- A guest whose entire order budget is too low just leaves; no rep feedback, no story line. This is a silent money-on-the-floor situation with no diagnostic.
- Rush ability (2/day, 0.7× cook speed) is a powerful lever that is never explained in prep or build screens.
- Contract simulation reuses the same actor system but through a boolean gate (`closedForOrder`). Testing regular service doesn't cover contract flow and vice versa.

---

## 5. Reputation

**How it works.** `progress.reputation` (0–100) → `expectedGuests = 5 + reputation×0.35`. Starts at 10 (~8 guests).

Reputation changes: happy guest +1, unhappy guest −1, `tier.rating` per dish served (Budget −6, Standard 0, Premium +6), contract outcomes, day events.

Wallet distribution: `wealthy = 0.10 + 0.06×rating`, `thrifty = clamp(0.45 − 0.06×rating, 0.10, 0.45)` where `rating = reputation/20`. Higher rep → richer crowd → more tips → upgrades → more rep. Main economic flywheel.

**Good.** The rep–wallet distribution link is the core positive feedback loop. It's elegant: serve quality food, get a better crowd, earn more.

**Issues.**
- Premium ingredients give +6 rep per dish served. A full Premium menu is worth +30–40 rep/day on top of normal guest happiness. This makes Farm delivery highly valuable beyond its tip bonus, but nothing in the supplier or dish screens shows this.
- Budget tier −6/dish means a new player on the budget market who doesn't know about tiers will watch their rep erode fast with no explanation.
- Rep display is 0–5 stars with 20-point bands. Rep can move 10 points (a large swing) with no visible star change, then jump a star suddenly. The dead zone discourages continued effort.
- Rep recovery at top is punishing: at reputation 90, a bad day with 10 unhappy guests (−10 rep) drops expected guests by 3.5. Takes 10+ good days to recover.

---

## 6. Economy

**Daily coin flow:**
```
Day start:  coins -= prepCost()         (ingredient buy)
During day: coins += sellPrice × served  (each sale)
During day: coins += tips                (per guest)
Settlement: coins -= wages              (player-controlled)
Passive:    coins += vendCash           (vending collection)
```

Single currency, no interest, no loans, no inflation.

**Good.** The settlement step making wages player-controlled is a meaningful daily decision. The break-even tension in early game (120 coins start, counter=40, grill=60) is intentional and correct.

**Issues.**
- `DayReport.wages` stays 0 after `finishDay()`; it's patched in `DayLog` via `applySettlement()`. Fixed: `applySettlement()` now returns `totalPaid`; `_postScores` uses that value instead of `report.wages`.
- `totalEarned` measures gross revenue, not profit. The leaderboard and goals built on it reward volume over efficiency.
- Vending machines at upgrade level 2 passively earn 20–30% of daily revenue with no ongoing player action. The box overflow mechanic (uncollected coins lost) is punitive but never explained.
- Recipe levelling ROI (~2× max price for 400 total coins) dwarfs any fixture upgrade at equivalent cost.

---

## 7. Contracts

**How it works.** `ContractBook.offerFor(day, diner)` returns a seeded contract or null. Player can accept (choosing crew ± closing doors), decline, or ignore. Payout is fixed; ingredient cost varies with current tier/supplier.

`whyNotTake` checks: team is non-empty, each contract dish has at least one crew member who can cook it, `coins >= ingredients(this)`.

**Good.** The crew selection mechanic adds a mini staffing puzzle. Closing doors for a full-team contract is a meaningful risk/reward trade.

**Issues.**
- Contract payout is not adjusted for ingredient tier. Farm delivery (1.25× cost) silently cuts contract margin 25%. Not communicated.
- Closed-for-contract is almost always the wrong choice. Guest revenue on even a poor day usually exceeds the incremental payout from full-team dedication.
- Contract state is day-indexed (`contractDay == progress.day`) but not explicitly serialized as an enum. If `progress.day` were corrupted or rewound, contract state silently breaks.
- `crewIds` holds staff IDs. IDs never reset (`_nextId` increments forever), so stale IDs in `crewIds` can't accidentally match a new hire. This is safe but the assumption is implicit.

---

## 8. Progress / Levelling

**How it works.** `xpToNext = 120 × level`. Levelling unlocks dishes, expands `menuSlots` (+1 every 2 levels), unlocks fixtures, opens plot sections, grants 5 gems.

Plot cost: `pricePerTile=6`, each section costs ~tiles×6 × (1 + 0.35×sectionsOwned). Level gate is usually the binding constraint, not price.

**Good.** Level-gating is clean. The plot expansion system (13 sections, dependency chain) gives the player a clear visual goal.

**Issues.**
- XP gain per day is now shown in the settlement screen.
- Level-up auto-adds dishes to the menu without asking. This can displace a profitable dish or add one with no machine. `declined` prevents it, but the player must preemptively decline dishes they haven't unlocked yet.
- `progress.day` is the single source of truth for day number, event seeding, contract seeding, and challenge gating. It is never validated on load (`fromJson` only clamps it). A corrupted or hacked day counter breaks all four systems silently.
- `Upgrade.supply` (3 levels, 540 total coins) reduces market spoilage. Becomes worthless on Standard/Farm.

---

## 9. Regulars

**How it works.** `Regular` has fixed `Wallet`, `Temper`, `favourite`. Points 0–15 (3/heart, 5 hearts max) drive:
- Visit chance: `0.35 + 0.1×hearts` (35%–85%).
- Tip multiplier: `1 + 0.08×hearts` (100%–140%).
- Patience multiplier: `1 + 0.06×hearts` (100%–130%).
- Friend chance: `0.08×hearts` per visit.

Join chance: 12% of satisfied unique guests if `book.people.length < cap(level)` where `cap = 3 + level`.

**Good.** The hearts-as-loyalty mechanic is well-calibrated. The drift mechanic (points fall after 10 days absent) is a sensible churn model.

**Issues.**
- Name pools previously had 14/13/9 names per gender against a cap of 3+level. At cap 17 (level 14), birthday-paradox collision probability was ~40%, silently blocking new regulars from joining. Fixed: name pools expanded to ~24 per gender.
- Drift is too lenient. A 5-heart regular has 85% visit chance; failing to show 10 consecutive days is ~0.2%. In practice high-heart regulars never drift. The mechanic only applies to low-heart regulars who already have low visit chance.
- Regulars list shows name and hearts but not favourite dish. Removing that dish from the menu turns the regular into a stranger silently.
- A 5-heart regular (140% tips, 85% visit, 40% friend chance) is worth ~2× a stranger in EV. With a full capped regular book this is the dominant income source, but nothing in the UI surfaces the total regular EV or warns when a dish removal affects them.

---

## 10. Events & Challenges

**How it works.** `DayEvent.forDay(day, level)` returns a seeded event modifying `guestMul`, `costMul`, shown in prep subtitle. Challenges (`challengeDayDone`) are one-off intra-day goals awarding XP or coins.

**Good.** Events are known at prep time (subtitle), giving the player a chance to respond. This is the right information-timing design.

**Issues.**
- Event schedule is fully deterministic per day number. Experienced players can memorise bad days. No variance across playthroughs.
- `today.costMul` is recomputed each call from `DayEvent.forDay(progress.day, progress.level)`. If level changes mid-day (impossible currently — XP batch-applies at day end) the cost multiplier would shift.
- Challenge rewards are modest (50 XP, 30 coins at level 10 where `xpToNext=1200`). Challenges are flavour, not meaningful goals.
- Events don't interact with contracts. A supply-shortage day raises `costMul` for contract ingredients too; the player may accept a contract that becomes unprofitable without realizing it.

---

## Cross-System Priority Table

| Issue | Systems | Impact |
|---|---|---|
| Morale has no live effect | Staff, Service | Fixed: morale now modulates paceMul (0.9–1.0×). |
| Tier downgrade is silent | Supplier, Dish | Fixed: settlement screen warns which dishes downgrade. |
| Budget market is dominated | Supplier, Economy | 20% cost saving offset by −6 rep/dish and spoilage. Standard almost always better. |
| Recipe ROI >> fixture ROI | Menu, Economy | Level 1→5 recipe: 2× price for 400 coins. No upgrade at equivalent cost comes close. |
| `report.wages = 0` | Economy, DayReport | Fixed: `applySettlement()` returns `totalPaid`; score post uses actual wages. |
| Regular name collision | Regulars | Fixed: name pools expanded to ~24 per gender. |
| Premium rep bonus invisible | Reputation, Supplier | +6 rep/dish from Premium not shown in dish or supplier screens. |
| Spoilage feedback | Supplier, Service | Story line exists but doesn't surface on the settlement screen — added note. |
| XP gain opaque | Progress | Fixed: XP earned now shown in settlement screen. |
| `supply` upgrade wasted | Economy, Supplier | Worthless on Standard/Farm. No guard against buying it on a better supplier. |
