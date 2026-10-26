# Tiny Diner Tycoon: Product Requirements Document

| | |
|---|---|
| Working title | Tiny Diner Tycoon (app title in `main.dart`; repo and package are still named `hex`) |
| Android id | `com.niche.diner` |
| Version | 1.0.0+1 |
| Status | In development, feature-rich, pre-release |
| Engine | Flutter / Dart (SDK ^3.11.5), portrait only |
| Document type | Retrospective PRD. It describes what the code does today and marks proposals and gaps as such. |

> **Read this first.** This PRD was written from the source tree, not from a design brief. Anything stated as a number (prices, durations, thresholds) is read from code and is accurate as of branch `dev/v1/sid/oct/22/ui`. Goals, audience and success metrics (section 2) are **inferred** and need the owner's confirmation. Section 15 lists what is stale or missing.

---

## 1. Summary

A single-player, mobile, isometric pixel-art restaurant management game. The player lays out a diner on a grid, hires and trains staff, sets a menu and prices, and then watches a two-minute service day play out in real time. Guests queue, sit, order, eat and pay. Staff cook and carry. At the end of the day the player sees what they earned, spent and kept, and uses that to expand the room, upgrade the kitchen and improve the team.

The game is two modes on a loop:

- **Build phase**: calm, tactile, no clock. Place fixtures, hire, price, shop for ingredients.
- **Service phase**: a 300-tick day (120 seconds at 1x). The player mostly watches, with light intervention (rush an order, clear a table, change speed).

The design bet is that the *layout is the puzzle*. Where the counter, grill, tables and pass go decides how far people walk, and that decides how many guests you can feed.

## 2. Goals, audience, success (inferred, to confirm)

### 2.1 Product goals
1. A satisfying "one more day" loop: roughly 3 to 5 minutes per day including build time.
2. Readable simulation. The player can always see *why* a day went well or badly (waits, walkouts, spoilage, wages), and the game says so in plain words (`advice.dart`, `MoneyView.savings`, `supplierHint`).
3. A coherent pixel-art identity that does not read as an AI/"dark fantasy" template (see `CLAUDE.md` UI rules).
4. Offline-first with optional Android cloud backup and leaderboards.

### 2.2 Target audience (proposed)
Casual to mid-core mobile players who like Kairosoft-style management games (Game Dev Story, Pocket Academy, Mini Metro-style readability). Short sessions, deep optimisation, no timers or energy.

### 2.3 Success metrics (proposed, none are instrumented today)
There is no analytics code in the repo. Suggested first set:

| Metric | Why |
|---|---|
| Completion of the 5-step first-day coach | Onboarding health |
| Day 1 / Day 7 retention | Loop strength |
| Median days played per session | Session length |
| Goals completed per player | Whether goals double as tutorial |
| Gem pack conversion, share buying styles | Monetisation viability |
| Share of players who open the Report screen | Whether the feedback loop is being used |

## 3. Core gameplay loop

```
        ┌───────────── Build phase ─────────────┐
        │ place/move fixtures · hire/train      │
        │ set menu + prices · buy portions      │
        │ expand plot · buy upgrades            │
        └───────────────────┬───────────────────┘
                            ▼  Start day
        ┌───────────── Service phase ───────────┐
        │ guests arrive → queue → seat → order  │
        │ → cook → carry → eat → pay → leave    │
        │ player: rush ×2, clear tables, speed  │
        └───────────────────┬───────────────────┘
                            ▼  closing + last call
        ┌───────────── Summary ─────────────────┐
        │ takings, tips, wages, waste, rating,  │
        │ xp/level, goals, advice, full report  │
        └───────────────────┬───────────────────┘
                            ▼  Next day
```

The phase is a three-value enum (`Phase { build, service, summary }`) in `build_screen.dart`. The layout can only change in build: "once the doors open, you live with it".

## 4. Progression and economy

### 4.1 Currencies
| Currency | Source | Sink |
|---|---|---|
| **Coins** | Sales, tips, catering, vending | Fixtures, ingredients, wages, hiring, training, upgrades, plot sections, recipe levels |
| **Gems** | Real-money packs (100 / 550 / 1200) | Wallpapers and floors only (30 to 50 gems each). Never pay-to-win. |
| **XP** | Serving guests | Restaurant level (`xpToNext = 120 × level`) |
| **Reputation** (0 to 100, shown as 0 to 5 stars) | Day performance | Decides how many guests come |

Starting state: 120 coins (`Diner.starter`), reputation 10 (an unknown place), one weak starter employee, a grill, two counters, two tables, two chairs, a plant, a rug.

### 4.2 Reputation and demand
- Expected guests per day = `round(5 + reputation × 0.35)`. A new place gets about 8 guests; a famous one about 40.
- At day end: `score = 100 × (0.75 × fedShare + 0.25 × speed) + tierBonus`, where speed falls to zero at an average 20 seconds' wait. Reputation moves **30% of the way** to the score, so one day never swings it far. Days with fewer than 4 guests move it half as much.
- Quality tier adjusts the score: Budget −6, Standard 0, Premium +6.
- A missed catering order costs 2 points. A critic or blogger verdict moves rating on its own.
- Wallet mix improves with rating: richer crowd, fewer thrifty guests.

### 4.3 Levels (restaurant level 1 to 99)
Level gates content. Known unlocks:

| Level | Unlocks |
|---|---|
| 1 | Burger, grill, counter, table, chair, plant, rug |
| 2 | Hot dog, fries, fryer, bench, long table, jukebox, low wall, "Room to the right" |
| 3 | Cheeseburger, soda, soda machine, takeaway window, wall TV, pass, kitchen floor, "Room behind", "Room to the left", Farm supplier, premium ingredients, food blogger days |
| 4 | Coffee, onion rings, espresso machine, "Room behind, right", food critic days |
| 5 | Pizza, chicken sandwich, pizza oven, "Room further back" |
| 6 | Ice cream, nuggets, freezer |
| 7 | Milkshake |
| 8 | Bacon double |
| 9 | Sundae |
| 10 | "The last room, right" (final plot section) |

### 4.4 Upgrades (`Upgrade` enum; price = base × next level)
| Upgrade | Max | Base | Effect |
|---|---|---|---|
| Faster kitchen | 5 | 80 | Every machine cooks 8% quicker per level |
| Quicker checkout | 2 | 60 | Counter payment takes 3 → 1 ticks |
| Cosy seating | 5 | 70 | Guests wait 15% longer per level (base patience 70 ticks) |
| Staff room | 3 | 120 | +1 team place (limit starts at 1) |
| Bigger tray | 1 | 150 | Staff carry 5 dishes, not 3 |
| Vending machine | 2 | 150 | Passive street income (see 5.9) |

Recipe levels run 1 to 5: price +25% per level, cook time −6% per level, cost `40 × level`.

### 4.5 Plot expansion
A 10-wide by 13-deep plot, bought in 13 sections. Each section needs the one nearer the street first, plus a level. Price = `tiles × 6 × (1 + 0.35 × sectionsOwned−1)`, rounded to 10. The room is always one connected shape.

## 5. Systems

### 5.1 Build system (`diner.dart`, `build_screen.dart`, `layout_group.dart`, `catalog.dart`)
- Isometric grid, 16 art px per cell. Four facings (`se`, `sw`, `nw`, `ne`); only `sw`/`nw` are drawn, the others are mirrors.
- **19 fixture kinds** in five shelf categories: Seating, Tables, Kitchen, Walls and floors, Decor.
- Roles: station, counter, seat, table, window, pass, decor.
- Special placements: **walls and passes sit on tile edges** (not tiles); **TV hangs on a wall**; **kitchen floor** is painted per tile (staff walk it, guests don't); rugs are floor-level.
- Interactions: place, nudge, rotate, move, copy, sell (50% refund), multi-select group move/copy, **undo (20 steps, coins included)**, pinch-zoom and pan.
- Validation with plain-language refusal (`PlaceResult.message`): outside the room, taken, blocks the door, would cut off part of the room, someone standing there, locked, needs a free tile beside it, and so on. A reachability check stops the player from walling off seats.
- Auras on decor: Plant (−8% patience drain, radius 1), Jukebox (+25% tips, radius 3), Wall TV (patience drain ×0.6, radius 4). Placement previews show the affected tiles.
- The diner needs a minimum set before it can open (`Report.missing`), and broken fixtures are flagged with a reason.

### 5.2 Menu and ingredients (`recipes.dart`, `menu_screen.dart`, `dish_screen.dart`, `prep_screen.dart`)
14 dishes on 6 stations:

| Dish | Station | Course | Cook (ticks) | Price | Unlock | Skilled |
|---|---|---|---|---|---|---|
| Burger | Grill | Main | 7 | 8 | L1 | |
| Hot dog | Grill | Main | 8 | 10 | L2 | |
| Cheeseburger | Grill | Main | 9 | 12 | L3 | |
| Bacon double | Grill | Main | 13 | 20 | L8 | yes |
| Fries | Fryer | Side | 5 | 5 | L2 | |
| Onion rings | Fryer | Side | 6 | 7 | L4 | |
| Chicken sandwich | Fryer | Main | 11 | 15 | L5 | |
| Nuggets | Fryer | Side | 7 | 8 | L6 | |
| Soda | Soda machine | Drink | 3 | 4 | L3 | |
| Coffee | Espresso | Drink | 5 | 6 | L4 | yes |
| Milkshake | Freezer | Drink | 5 | 8 | L7 | |
| Pizza | Oven | Main | 14 | 18 | L5 | yes |
| Ice cream | Freezer | Dessert | 3 | 6 | L6 | |
| Sundae | Freezer | Dessert | 4 | 9 | L9 | |

- A guest orders one main, plus a side (55%), drink (65%) and dessert (30%) **if the menu has them**.
- **Quality tiers**: Budget (×0.92 price, cost 18% of menu price, −6 rating), Standard (×1.0, 26%, 0), Premium (×1.18, 38%, +6; needs recipe level 3).
- **Morning portions**: the player chooses how many portions of each dish to prepare. Too few sells out; too many is thrown away at closing and counted as waste.
- **Pricing**: the player sets each price. A guest's wallet decides what they'll accept (see 5.4).
- **Special**: one dish can be the special (×0.8 price, ×1.1 demand). A sandwich board appears outside the door.
- **Suppliers**: Budget market (×0.8 cost, 10% or sometimes 35% of portions arrive spoiled), Usual supplier (×1.0), Farm delivery (×1.25 cost, +10% tips, unlocks L3).

### 5.3 Service simulation (`service.dart`, `clock.dart`, `diner.dart`)
- **Deterministic fixed-step sim**. `TickClock` converts frame time to whole ticks (0.4 s each; max 5 catch-up ticks per frame, the rest dropped). The sim never reads the wall clock, so it is fast-forwardable and testable.
- Day = 300 ticks of arrivals, then **150 ticks of last call** for guests still inside. Eating takes 14 ticks.
- Speeds: Pause / 1x / 2x / 3x.
- Guest state machine: `arriving → queued → toSeat → waiting → eating → toPay → paying → leaving`.
- Order-item state machine: `pending → claimed → cooking → ready → onPass → carried → delivered` (or `lost`).
- Staff state machine: `idle, toPickup, toLoad, toDeliver, toClean, toShelf, fromShelf`.
- Pathfinding is cell-based on orthogonal neighbours; walls block edges; guests can't enter kitchen tiles.
- **Player interventions during a day**:
  - Rush a waiting guest (2 per day; their food cooks 30% faster).
  - Tap a messy table to clear it.
  - Tap a guest to see wallet, temper and mood.
  - Change speed; pause.
- Mess: dirty tables slow guests' patience (×0.65) and cut tips (×0.5).
- Cues (`cues.dart`): the sim records `enter, cookStart, dishReady, plate, paid, paidWell, walkout`; the screen decides which sound to play. The sim never touches audio.

### 5.4 Guests (`guests.dart`, `regulars.dart`, `service.dart`)
- **Wallet**: Thrifty (accepts up to 1.0× recipe price, tips ×0.5), Regular (1.3×, ×1.0), Big spender (1.8×, ×1.6).
- **Temper**: Hasty (×0.7 patience, 25%), Steady (×1.0, 55%), Easygoing (×1.35, 20%).
- **Identity**: gender (47% women, 47% men, 6% non-binary), a name from a list per group, and a body look from six figures (`cust_a` to `cust_f`).
- **Arrival channels**: on foot (queue at the door), by car (takeaway window / drive-through lane), regulars, walk-in job applicants (14% chance), critic, blogger.
- **Regulars**: a favourite dish, fixed wallet and temper, and *fondness* of 0 to 15 points (3 per heart, 5 hearts). Fonder regulars come more often, tip more, wait longer and may bring a friend. Happy guests become regulars at 12%. They drift away after 10 days unvisited.
- **Day events** (`events.dart`; 42% of days after day 1, fixed by the day number so the morning notice is always right):

| Event | Effect |
|---|---|
| Lunch rush | 35% of guests arrive in one bunch at midday |
| Rainy day | Foot traffic ×0.75, cars ×1.7 |
| Street festival | Guests ×1.4, +35% chance of thrifty |
| Quiet day | Guests ×0.7 |
| Supplier shortage | Ingredient cost ×1.35 |
| Food critic (L4+) | Only premium impresses; moves rating directly |
| Food blogger (L3+) | Wants fair prices and a short wait; moves rating directly |

Never two reviewers on back-to-back days.

### 5.5 Staff (`staff.dart`, `traits.dart`, screens `staff_*`, `hiring_*`, `person_*`, `training_*`)
- **Four stats, 1 to 10**: Cooking (sale price, tips), Speed (walk pace), Service (plate handling time), Charm (patience, tips). Each has a hidden **potential cap**.
- **Mastery**: counts dishes made; levels at 8 / 25 / 60 dishes give +4% price and −8% cook time per level. *Skilled* dishes (pizza, coffee, bacon double) need mastery ≥ 1, either from a speciality, from making enough, or from a 150-coin course.
- **Roles and tasks**: everyone can cook at chosen machines, plus tasks `serve`, `clear`, `window`. The player can restrict a person to given machines and set a preferred machine.
- **Traits (10)**: Quick hands, Cheerful, Perfectionist, Fast learner, Frugal, Team player, Clumsy, Hot-headed, Loyal, Late bloomer. A candidate shows one; the rest are discovered over time or when they bite.
- **Pay and morale**: wages are paid daily. A missed payday drops morale (0 to 3); at 0 they quit. Hot-headed lose two; Loyal take two missed days to lose heart.
- **Training**: one lesson per person per day (a stat point, or a dish), cost `15 × currentStat` (−30% for Fast learner).
- **Hiring**: no one applies unless an advert is paid for. Notice board 30 coins (2 beginners), Local paper 90 (3 average), Hiring agency 240 (3 experienced, many specialists). Walk-ins cost two days' wages to hire rather than four.
- **Wages**: `2 + 0.5 × statTotal + 0.25 × headroom`, modified by traits, +15% for a specialist. Severance one day's wages.
- Each person keeps a short memory log (last 5 events), plates served and dropped.

### 5.6 Catering (`contracts.dart`, `order_screen.dart`)
40% of days after day 1 offer an order from one of 8 clients (office, birthday party, school bake sale, book club, football team, wedding, depot night shift, film crew). Pays about 1.5× menu price for a fixed list of dishes by closing time. The player picks a crew who stop serving the floor, or shuts the doors for the day. Missing it costs the ingredients and 2 rating. Offer is a pure function of day, rating and menu.

### 5.7 Goals and tutorial (`goals.dart`, `coach.dart`, `guide.dart`)
- **Coach**: a five-step first-day prompt chain ("Welcome. Tap Build…" through "That was a day…"). Each step completes by doing it. Position is saved so restarts don't replay it.
- **Guide**: 15 pages of up to three short lines each, with pictures, openable from Goals or Settings, skippable.
- **Goals**: about 25, doubling as tutorial (open the doors, serve 10, reach L2, 2-star rating, fries, set a price, hire a second person, clear 5 tables, buy the room to the right, TV, a day with no angry exits, takeaway window, 5 cars, keep 300 in a day, impress critic, win over blogger, a special, catering order, vending machine, try another supplier). Each carries a `hint` that says how.

### 5.8 Analysis and feedback (`report_screen.dart`, `stats_screen.dart`, `advice.dart`, `crowd.dart`, `money.dart`)
- **Day report**: served, walkouts, takings, tips, wages, ingredients, waste, spoilage, average wait, stars (0 to 3), XP, level-ups, rating before/after, regulars seen/joined/gone, staff mood changes, event, catering result, vending result, and a story of highlights.
- **Stats**: crowd by gender, wallet and dish, busiest hours (8 slots), best/worst/average days, event vs plain days, line chart over the last **60 days** (`DayLog.keep`), pie and column charts.
- **Advice**: one plainly worded change worth making after each day, only when something stands out.
- **Money view**: shares of income going to wages, ingredients, waste, spoilage, with up to three savings tips.

### 5.9 Vending machines (`vending.dart`, `vending_dialog.dart`)
Passive street income, up to 2 machines. Cold drinks (price 3, cost 1, 13% of passers-by stop) or Snacks (price 5, cost 2, 11%). Stock 18 per machine, coin box holds 150, 7% daily breakdown chance costing 20 to repair. The player collects takings by tapping the machine, and can switch it off. Weather and events modify demand; the second machine reaches fewer new people.

### 5.10 Cosmetics (`styles.dart`, `style_popup.dart`)
Wallpapers: Mint (default), Cream, Sage free; Rose, Navy 30 gems; Striped, Brick 50 gems. Floors: Peach (default), Slate free; Wood, Terracotta, Mint tile 30; Black and white 40. Owned permanently. Art is generated per style id (`_s_<id>` suffix).

## 6. Screens and navigation

| Screen | File | Job |
|---|---|---|
| Title / Home | `home_screen.dart` | Continue, new game, saved games (slots), settings |
| Build / Service / Summary | `build_screen.dart` (3,003 lines) | The main board; all three phases |
| Pause menu | `pause_menu.dart` | Resume, sound/music, settings, guide, title |
| Shelf popup | `shelf_popup.dart` | Buy fixtures by category |
| Menu | `menu_screen.dart` | One line per dish, switch on/off |
| Dish | `dish_screen.dart` | Ingredients, tier, recipe level, price, special |
| Today's portions | `prep_screen.dart` | Portions per dish, supplier |
| Upgrades | `upgrade_screen.dart` | Kitchen, staff room, tray, vending |
| Expand | in `build_screen.dart` | Plot sections |
| Staff / Hiring / Person / Training | `staff_screen.dart`, `hiring_screen.dart`, `person_screen.dart`, `training_screen.dart` | Team management |
| Catering order | `order_screen.dart` | Accept, pick crew |
| Vending dialog | `vending_dialog.dart` | Stock, collect, off switch |
| Day report | `report_screen.dart` | Everything about one day |
| Stats | `stats_screen.dart` | Charts and patterns |
| Goals | `goals_screen.dart` | Next, later, done |
| Guide | `guide.dart` | How to play |
| Settings | `settings_screen.dart` | Sound, music, volume, backup, scores |
| Save panel | `save_panel.dart` | Copy/paste the save as a code |
| Style popup | `style_popup.dart` | Wallpaper and floor, gems |

Navigation is push-based with **instant cuts** (`_CutTransitions`); there are no page animations by design.

### UI rules (from `CLAUDE.md`, treated as product requirements)
- Banned: emoji, glow, gradients, wide-tracked caps, glass panels, ambient particles, bounce curves, one-radius-for-everything, symmetric stacks, generic copy.
- Required: a defined type scale, colour from `Pal` only with one accent, a 4/8/12/16/24 spacing scale, flat elevation, one clear primary action per screen.
- Diner screens stay light: about five facts visible; a card has at most three lines; help appears inline next to what was tapped; text is never clipped; news is a small self-dismissing toast; buttons say what they do and what you get ("Extend dining room: +2 rows"); people and things are listed as compact rows with details on their own page.

## 7. Art direction

### 7.1 Style
Isometric, hard-edged pixel art, flat colours, warm light from the upper left (tops brightest, left faces mid, right faces darkest; shadows lean cool, lights lean warm). Cheerful and slightly cosy rather than dark. The palette (`tools/gen_diner_art.py`) includes cream, peach, wood, mint, steel, red, pink, blue, green, marble, gold, grass, sand, clay on an ink `#2a2036` outline.

### 7.2 Generated, not hand-drawn
All diner art is **procedural**. `tools/iso.py` is a tiny isometric toolkit (world-to-screen projection `x = u − v`, `y = (u + v)/2 − z`, 32×16 diamond per cell). `tools/gen_diner_art.py` (2,123 lines) draws every fixture, tile, building, car and icon, and `tools/people.py` draws parametric chibi characters from a spec (skin, hair, outfit). Output is `assets/diner/*.png` plus `manifest.txt` (name, size, anchor, trim box). **Never hand-edit the PNGs**; edit the generator and re-run.

### 7.3 Asset inventory (~330 sprites in `assets/diner/`)
- **Fixtures** with four facings: counter, grill, fryer, soda, espresso, oven, freezer, chair, bench, table, long table.
- **Decor**: plant, jukebox, TV (`tv_se/sw`), rug, special board, door (open/closed).
- **Room shell**: wall variants (A/B, board, window, corner, edge), front walls with window frames, pass edge, low wall, per-style wallpapers and floors (`_s_<id>`), kitchen floor.
- **People**: 6 customer looks (`cust_a` to `cust_f`) plus chef and waiter, each at 2 facings (`nw`, `sw`) with frames `0..3` walking, `s0, s1` standing, `sit` seated.
- **Emotes** (6): coin, heart, oops, sigh, star, yuck. **Mood** (4 levels): `mood_0` to `mood_3`.
- **Food**: `ico_<dish>` icons and `plate_<dish>` for each dish.
- **Town**: concrete, road (dashed, vertical), crosswalks, kerb, sidewalk, plaza, grass, park, car park with bays, buildings (blocks, flats, shops: arcade, bakery, cafe, laundry), trees (broad, pine, street), fountain, bus stop, post box, bin, hydrant, bollards, bike rack, bench, street lamp, hedge, flower bed.
- **Vehicles**: 3 cars (red, blue, sun) × 4 facings.
- **Vending** (on/off/with cash), takeaway window front pieces (`front_win_r0/r1`), `coin`.
- **UI icons** (`assets/pixel/sprites.txt`, 1,635 lines): a hand-authored palette-indexed sprite sheet, referenced in text as `:name:` tokens and rendered by `PxText`. It currently also contains **legacy units from an earlier card/overworld prototype** (hero, knight, golem, titan, spells, bridges, etc.); see section 15.

### 7.4 Pixel-grid discipline
`PixelUi.unit` is the size of one art pixel and always a whole number of device pixels. `PixelTextScaler` snaps every font size to a multiple where one VT323 font pixel is a whole device pixel. No fractional scaling, rotation, blur, gradient or fade anywhere.

## 8. Typography and text

- **Font**: VT323 (bundled, OFL licence in `assets/fonts/OFL-VT323.txt`). Line height tightened to 1.05 in the theme. No `letterSpacing`.
- **Type scale**: current code still contains ad-hoc sizes (16, 17, 18, 22). The UI rules require a defined 3 to 4 size, 2 weight scale in `ThemeData`. This is an open item (section 15).
- **Tone of copy**: plain, specific, second-person, small-diner warmth. Examples from code: "Guests queue outside, sit down, order, eat and pay."; "A table with no chair beside it seats nobody."; "Took 140, costs 95"; "Another missed payday and they quit."
- **Rules of thumb in the existing copy**: sentence case; buttons name the outcome; errors say what to do ("Needs a free tile beside it"); no motivational filler.
- **Text inventory** (all English, hard-coded in Dart; no i18n layer):
  - Fixture, upgrade, supplier, trait, stat and event descriptions (`FixtureDef.info`, `UpgradeDef.info`, `Supplier.blurb`, `TraitInfo.info`, `StatInfo.info`, `DayEvent.blurb`).
  - Refusal messages (`PlaceResult.message`, `StaffResult.message`).
  - Goal titles and hints (about 25), coach steps (5), guide pages (15).
  - Name pools: women 14, men 13, non-binary 9, plus staff names (`_names`), catering clients (8).
  - Generated sentences: `Contract.summary`, `MoneyView.savings`, `supplierHint`, day-report story lines, staff `moodNote`.
- **Localisation**: not supported. All strings are inline. Adding a locale means extracting roughly every user-facing string; flag as a post-1.0 decision.

## 9. Animation and motion

Motion is deliberately minimal and **steps in whole pixels**.

| Element | Behaviour |
|---|---|
| Walking people | 4-frame walk cycle per facing (`_0`..`_3`), interpolated between cells using the tick clock's `alpha` |
| Standing / seated | `s0/s1` idle pair, `sit` frame |
| Emotes | A 6-sprite set shown above a head for 8 to 10 ticks (`Person.feel`): sigh, yuck, coin, heart, oops, star |
| Patience / cooking meters | A bar above the head (`Meter.patience`, `Meter.cooking`) |
| Order bubble | Small dish icon(s) above a waiting guest |
| Coins | A coin rises off a paying guest (`Pop`) |
| Door | Open/closed sprite, tied to day state |
| Street | Pedestrians on the far pavement as a pure function of the step; cars drive the lane and pull into the window |
| Section purchase | Selected/bought section lights up for a moment: 3 steps down to 0 |
| Toasts | Small, top-left, self-dismiss after 5 s |
| Screen entrance | `Entrance` fades-in with a stagger of 360 ms + 70 ms per index (an exception to the "no fades" rule; review) |
| Pulse | 800 ms controller used for attention |
| Page transitions | Instant cut |
| Camera | Pinch-zoom and pan on the board; zoom buttons; whole-pixel snapping |

**Rendering performance**: the ground, floor and walls are drawn once into a cached picture and reused until a layout change (`diner_painter.dart`). During drag/pinch the cache is skipped. The tick clock only notifies listeners on a new tick unless something is mid-step.

## 10. Audio

All sound is **synthesised by code**. `tools/gen_sounds.py` produces 8-bit-style WAVs from square / triangle / noise voices; edit the script, re-run, restart. Never hand-edit the WAVs.

### 10.1 Effects (19)
| Sfx | Purpose | Priority |
|---|---|---|
| tap, tick | UI taps | 0 |
| no | Refused action | 1 |
| place, thud | Fixture placed / dropped | 1 |
| coin, till, till_big | Payment; big tip | 1 / 1 / 2 |
| chime | Guest enters | 1 |
| sizzle | Machine starts a dish | 0 |
| ding | Dish ready | 1 |
| plate | Plate reaches table | 0 |
| grumble | Guest walks out | 2 |
| bell_open, bell_close | Day start / end | 3 |
| jingle_good, jingle_bad, jingle_up | Good day, bad day, level-up | 3 |
| warn | Warning | 2 |

### 10.2 Music (2 loops)
- `music_build`: calm, 84 BPM, 8 bars.
- `music_service`: busy, 116 BPM, 8 bars.

### 10.3 Behaviour (`audio/sound.dart`)
- Every sound plays through `Sound.instance`, never directly through `audioplayers`.
- Each effect has a **priority**, a **minimum gap** (ms) and a volume. Higher priority wins when too many want to play, and repeats are rate-limited.
- Sim cues map to sounds through `sfxFor(Cue)`; the sim itself is silent.
- Settings: effects on/off, music on/off, each with level low / medium (default) / high (0 to 2). `watchLifecycle()` pauses music in the background. A `SoundBackend` interface lets tests swap in a recording backend.

## 11. Technical architecture

### 11.1 Stack
Flutter, Material 3 dark theme with all defaults overridden to the pixel kit. Packages: `hive_ce` + `hive_ce_flutter` (storage), `audioplayers` (sound), `games_services` 5.0.0 (Play Games), `in_app_purchase` (gem packs), `cupertino_icons`. Dev: `flutter_lints`, `flutter_test`.

### 11.2 Layers
```
lib/
  main.dart          bootstrap: Storage → PixelAssets → DinerArt → Sound; portrait lock; theme
  diner/             game logic + screens (≈ 17k lines)
    diner.dart       Diner model: grid, fixtures, plot, economy, undo, save/load (pure Dart)
    service.dart     DinerSim: the day (pure Dart, tick-based)
    recipes.dart  staff.dart  traits.dart  guests.dart  regulars.dart
    contracts.dart  events.dart  goals.dart  vending.dart  suppliers.dart
    crowd.dart  money.dart  advice.dart  city.dart  luck.dart  clock.dart  cues.dart
    build_screen.dart  diner_painter.dart  iso.dart  actor.dart  diner_sprite.dart  diner_art.dart
    *_screen.dart  *_popup.dart  toast.dart  title_sign.dart
  data/              storage (Hive), cloud_save, save_sync, play_games_store,
                     leaderboards, gem_shop
  audio/sound.dart   Sfx / Music / Sound.instance
  ui/                widgets.dart (Panel, GoldButton, Choice, Tag…), pixel_*.dart charts,
                     pixel/ (palette, assets, UI kit, text scaler)
  game/              LEGACY hex-grid prototype (hex.dart, models.dart)
tools/               Python art + sound generators
assets/              diner/ (PNG + manifest), pixel/sprites.txt, sounds/, fonts/
test/                51 test files
```

### 11.3 Key design decisions
1. **Logic is pure Dart.** `diner.dart`, `service.dart`, `staff.dart`, `recipes.dart` and friends import no Flutter, so they are unit-testable and the sim can run headless and fast-forwarded (`diner_drive_test`, `diner_bench_test`).
2. **Fixed-step simulation.** One tick = 0.4 s. Determinism from the tick, not the frame rate.
3. **Day-seeded luck.** `dayLuck(day, salt)` (a bit-mixed hash) fixes events, catering offers and spoilage by the day, so the morning's notice is always true and re-looking never changes the answer. Random streams for in-day behaviour are seeded by day.
4. **Sim reports, screens decide.** The sim emits `Cue`s and `StoryLine`s; the UI turns them into sound and toasts.
5. **Sprites are looked up by name**, with `manifest.txt` giving size, anchor and trim box. `DinerArt` loads them all at start-up.
6. **Everything is serialisable to plain JSON** with defensive `fromJson` (clamps, type checks, defaults), so older saves load and corrupt fields don't crash.
7. **Layout edges are first-class.** Walls, hatches and passes live on `Edge(x, y, alongX)`, with a migration for older saves that stood them on tiles.

### 11.4 Rendering
`CustomPainter` draws the board in isometric. Depth sorting uses `Actor.depth` (default `x + y`). The static world (ground, floor, walls) is cached as an image and invalidated by a revision counter bumped on change (because `Diner` is mutated in place). Selection, ghosts, errors, group-move ghosts and plot outlines are overlay layers.

### 11.5 Testing
51 test files in `test/`, covering sim (service, rush, drive, hung, walk-in, tasks, pass), economy (money, gems, scores, goals), staff and traits, layout (edit, wall, walls, edge-wall, long-table, lift, expand, path), regulars, events, catering, cloud save, sound, settings, UX, zoom, phone layout, and asset presence (`assets_test`). Preview harnesses generate PNGs:
- `PIXEL_PREVIEW=<png> flutter test test/pixel_preview_test.dart`
- `UI_PREVIEW=<dir> flutter test test/ui_preview_test.dart`
- `DINER_PREVIEW=<png>` / `DINER_SCREEN=<png>` with `test/diner_preview_test.dart`

### 11.6 Build pipeline for generated assets
```
python tools/gen_diner_art.py   →  assets/diner/*.png + manifest.txt
python tools/gen_sounds.py      →  assets/sounds/*.wav
flutter run                     (restart; assets are not hot-reloaded)
```

## 12. Data, persistence and online services

### 12.1 Local save (`data/storage.dart`)
- One Hive box named `hex`, plain values, no adapters. If Hive isn't initialised (tests), an in-memory map is used.
- **Multiple save slots** (`Storage.slots`). Slot 1 uses the original key `diner` so no earlier player lost their game; others use `diner2`, `diner3`…
- Each slot is stamped with a time. Metadata ("Day 12, level 5, 840 coins") can be read without loading the whole diner.
- Preferences: sfx / music on, levels, auto-backup, post-scores, best score sent per board.
- `Storage.init()` failure is non-fatal: "progress will not be saved" is logged and the game runs.

### 12.2 Save code (`data/cloud_save.dart`, `save_panel.dart`)
The whole diner can be squeezed into a text code with a format marker and checksum, copied somewhere trusted and pasted back on another device. A truncated or altered code is detected and rejected with a plain-language reason.

### 12.3 Cloud backup (`save_sync.dart`, `play_games_store.dart`)
Android only, via Google Play Games. Compares phone and cloud saves by progress and time. Outcomes: same / upload / download / **ask the player** when they disagree about which is newer. A second of difference is ignored. Auto-backup after each day and on exit, on unless turned off. Never forces sign-in.

### 12.4 Leaderboards (`data/leaderboards.dart`)
Two Play Games boards: **Best day's profit** and **Total coins earned**. Only a new personal best is sent; never prompts for sign-in; can be turned off; boards without an ID are silently skipped.

### 12.5 Monetisation (`data/gem_shop.dart`)
Consumable gem packs (`gems_100`, `gems_550`, `gems_1200`) through Google Play via `in_app_purchase`. Safeguards: purchases are idempotent by order id, and gems bought while no game is open are held as `pendingGems` until a save can take them. Gems buy **cosmetics only**; there are no ads, timers or energy.

## 13. Platform and non-functional requirements

| Area | Requirement |
|---|---|
| Platforms | Android is the shipping target (Play Games, IAP, `com.niche.diner`). The repo also has iOS, macOS, web, Windows, Linux scaffolds; online features have no non-Android implementation and degrade to nothing. |
| Orientation | Portrait only, locked. |
| Performance | Fixed-step sim must cope with 3x speed. Frame catch-up capped at 5 ticks. Static scene cached. |
| Resolution | All drawing on the device-pixel grid; no fractional scaling. |
| Accessibility | Currently: large tap targets via the pixel kit, text never clipped, colour is not the only signal for placement validity (refusal text is given). Not present: screen reader labels, colour-blind palette, text size setting, reduce-motion. |
| Reliability | Defensive deserialisation; sim is deterministic; save is never lost on first-slot upgrade. |
| Privacy | No analytics or tracking code in the repo. Online features are opt-out and quiet. |
| Offline | Fully playable offline. Cloud features are optional. |
| Licences | VT323 under OFL. Other art and sound are generated in-repo. |

## 14. Release scope

### 14.1 In scope for 1.0 (already built)
Build/service/summary loop; 19 fixtures; 14 dishes; 13 plot sections; staff with stats, traits, mastery, morale, training and hiring; regulars; day events; catering; vending; takeaway window; goals, coach and guide; stats and advice; multi-slot saves; save code; Play Games backup and leaderboards; gem cosmetics; generated art and sound.

### 14.2 Candidates for post-1.0 (proposed)
- Localisation.
- More wallpapers, floors, fixtures and dishes; seasonal events.
- Accessibility pass (text size, colour-blind safe cues, reduce-motion).
- iOS release (Game Center, StoreKit).
- Cross-slot or cross-device sync beyond Android.
- Analytics (opt-in).

## 15. Risks, gaps and clean-up

| # | Item | Detail | Suggested action |
|---|---|---|---|
| 1 | **Repo naming mismatch** | Package, repo, `CLAUDE.md` and `README.md` say "hex"; the app is "Tiny Diner Tycoon". `CLAUDE.md` describes a "dark fantasy game" and `Pal.gold` accents, while the shipped art is bright and cosy. | Decide the name; update `README.md` (currently just `# hex`) and `CLAUDE.md`. |
| 2 | **Legacy hex prototype** | `lib/game/` (hex.dart, models.dart), `lib/ui/pixel/hex_art.dart`, the unit/spell sprites in `sprites.txt`, `design/gen_zones.py` and `docs/game-expansion.md` (overworld, summons, statuses) belong to an earlier game. `docs/game-expansion.md` does not describe this product. | Confirm and remove, or move to an `archive/` folder. Strip unused sprites. |
| 3 | **Monolith screens** | `build_screen.dart` is 3,003 lines and `service.dart` 3,680, `diner.dart` 2,308. | Split by phase/concern before adding major features. |
| 4 | **Type scale** | Ad-hoc font sizes remain; the rules require a defined scale in `ThemeData`. | Add the text theme and migrate. |
| 5 | **Motion exceptions** | `Entrance` uses a staggered fade; the rules say page and UI motion are cuts and steps. | Review against `CLAUDE.md`. |
| 6 | **No analytics** | Cannot measure any metric in section 2.3. | Add an opt-in event layer if metrics matter. |
| 7 | **No localisation** | All text inline. | Decide before the string count grows. |
| 8 | **Contract threshold** | `ContractBook.minRating = 0.0` ("zero for now… it was 3.5"). | Decide the shipped value. |
| 9 | **Missing-ID leaderboards / IAP** | Product ids and board ids must exist in Play Console. | Verify in the release checklist. |
| 10 | **Balance** | Constants are spread across files. No single balance sheet. | Consider a data-only balance file or tuning table. |
| 11 | **Platform claims** | Non-Android platforms are scaffolds only; behaviour untested here. | Decide the target list. |

## 16. Open questions for the owner
1. Final name, and is the repo to be renamed from `hex`?
2. Is the legacy hex/card game dead, or is it a planned second mode? (`docs/game-expansion.md` suggests it was once active.)
3. Intended session length and number of days to "finish" (is there an end state, or is it endless? Today it is endless: level cap 99, last plot at L10.)
4. Is gem spending cosmetics-only for good, or will convenience items arrive?
5. Android-only at launch, or iOS too?
6. Which success metrics matter, and is opt-in analytics acceptable?
7. Is the 2 rush-per-day cap and the 3x max speed final?

## Appendix A: Key constants

| Constant | Value | Source |
|---|---|---|
| Tick length | 0.4 s | `Pace.tickSeconds` |
| Day length | 300 ticks (2 min) | `Pace.dayTicks` |
| Last call | 150 ticks | `Pace.lastCall` |
| Eat time | 14 ticks | `Pace.eat` |
| Rushes per day | 2, food ×0.7 time | `Pace.rushPerDay`, `rushSpeed` |
| Base patience | 70 ticks | `Progress.patience` |
| Undo depth | 20 | `Diner.undoLimit` |
| Max recipe level | 5 | `Progress.maxRecipeLevel` |
| Starting reputation | 10 | `Progress.startReputation` |
| Start coins | 120 | `Diner.starter` |
| Plot price per tile | 6 (+35% per owned section) | `Diner.pricePerTile`, `priceRise` |
| Teach a skilled dish | 150 coins | `Diner.teachCost` |
| Staff max stat / morale | 10 / 3 | `Staff` |
| Mastery thresholds | 8 / 25 / 60 dishes | `Staff.masteryAt` |
| Walk-in applicant chance | 14% | `DinerSim.walkInChance` |
| Event chance | 42% of days | `DayEvent.chance` |
| Catering chance | 40% of days | `ContractBook.chance` |
| Regular join chance | 12% | `RegularBook.joinChance` |
| Regular drift after | 10 days | `Regular.driftAfter` |
| Vending: stock / box / break / repair | 18 / 150 / 7% / 20 | `Vending` |
| Day history kept | 60 days | `DayLog.keep` |
| Toast life | 5 s | `Toast.life` |
| Gem packs | 100 / 550 / 1,200 | `gem_shop.dart` |

## Appendix B: Source map

| Topic | Files |
|---|---|
| Economy, levels, upgrades | `recipes.dart` |
| Grid, fixtures, plot, undo, save | `diner.dart`, `layout_group.dart`, `catalog.dart` |
| Day simulation | `service.dart`, `clock.dart`, `cues.dart`, `luck.dart` |
| Guests and regulars | `guests.dart`, `regulars.dart`, `crowd.dart` |
| Staff | `staff.dart`, `traits.dart`, `staff_*.dart`, `hiring_screen.dart`, `person_screen.dart`, `training_screen.dart` |
| Events, catering, vending, suppliers | `events.dart`, `contracts.dart`, `vending.dart`, `suppliers.dart` |
| Teaching and feedback | `coach.dart`, `guide.dart`, `goals.dart`, `advice.dart`, `money.dart`, `report_screen.dart`, `stats_screen.dart` |
| Rendering | `diner_painter.dart`, `iso.dart`, `actor.dart`, `diner_sprite.dart`, `diner_art.dart`, `city.dart`, `pedestrians.dart` |
| Pixel UI kit | `ui/widgets.dart`, `ui/pixel/*`, `ui/pixel_*.dart` |
| Audio | `audio/sound.dart`, `diner/sound_toggles.dart`, `tools/gen_sounds.py` |
| Art generators | `tools/gen_diner_art.py`, `tools/iso.py`, `tools/people.py` |
| Persistence and online | `data/*.dart` |
