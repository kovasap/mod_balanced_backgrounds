# Balanced Backgrounds — Architecture & Balance Plan

This document specifies the complete mathematical model, UI/backend architecture, cross-mod compatibility strategy, and per-background stat/star/cost plan for **Balanced Backgrounds** (see [README.md](README.md)). All tunable constants live in [`mod_balanced_backgrounds/config/params.nut`](mod_balanced_backgrounds/config/params.nut) and can be previewed interactively with [`./simulate_bros.py`](simulate_bros.py).

---

## 1. Design Goals & Finalized Decisions

1. **Tight-Margin Linear Variance ("Sure-Thing" Highborn vs. Marginal-Edge Lowborn Prodigies)**:
   - **Linear Variance Reduction**: Starting attribute roll widths (`VarMult`) decrease linearly from Lowborn (`0.52×` at `-8.0 SSP`) down to Highborn (`0.10×` at `+45.0 SSP`), passing through `0.27×` at **Militia** (`S_adj = +23.3 SSP`).
   - **Marginal Lowborn Upset (~4 SSP Average Win, ~8 SSP 1% Outlier)**:
     - **Highborn / Premium Backgrounds** (`Hedge Knight`, `Gladiator`, `Adventurous Noble`, `Sellsword`, `Oathtaker`, `Swordmaster`) are a rock-solid **"sure thing"** (`Mean ≈ 44.5–46.0 SSP`, tight `SD ≈ 3.1–3.8 SSP`, `0–1` stars).
     - **Lowborn Backgrounds** (`Beggar`, `Refugee`, `Apprentice`, `Daytaler`, `Vagabond`) rely on broad `2★`-dominant growth (`5–7` talented attributes, rare `≤5%` `3★`) and average `~37–39 SSP` (`SD ≈ 6.0–6.7 SSP`). When a standout Lowborn beats a Highborn at Level 11 (`~12.3%` of random matchups), **the winning margin is tight (`+3.7 SSP` on average, with extreme `1%` `P99` outliers at `+8.9 SSP`)**.
   - **Highborn Starting Pending Level-Ups (`+1` to `+6` -> `Level 2` to `Level 7`)**:
     - Hireable Highborn backgrounds (`S_adj >= 33.5 SSP`, excluding Origin `Companion` and fixed `Level 9` Crisis recruits) **always start with `1` to `6` pending level-ups** (`28% / 26% / 20% / 13% / 8% / 5%` for `+1..+6`, mean `+2.62` pending levels) and pay Vanilla's steep power-law signing surcharge `floor(500 * N^1.5)` (`+500c` at `+1` up to `+7,348c` at `+6`, even when hired without equipment).
   - **Soft Midpoint Outlier Compression**: 98 of 133 backgrounds keep their exact Vanilla / Reforged / Hardened / XBE midpoints untouched; 35 extreme outliers (`S_0 < -1.5` or `S_0 > +42.0 SSP`) are soft-compressed into `[-3.0, +46.5] SSP`.
   - **Thematic `ExcludedTalents` Filtering & Origin Support**: Keep at most **1** thematic flaw (`RangedSkill`, `MeleeSkill`, `Deserter` `Bravery`, `Cripple` `Initiative`, XBE `Leper` `Hitpoints`), cap talented attributes at `open - 1` for Hardened's `Discovered Talent`, and apply Balanced Backgrounds star rules to Day-1 Origin rosters (while preserving Day-1 scenario starting levels).
2. **Stat-Driven Daily Wage & Character Signing Cost**:
   - `DailyWage` is a pure function of current `BaseProperties` (`~6–14/day` at Level 1 base stats, growing naturally as pending/earned level-ups are invested up to `~28–31/day` at Level 11).
   - `BaseHiringCost` combines Level-1 `BaseProperties` signing cost with `floor(500 * (Level - 1)^1.5)` for pre-gained pending level-ups; `TryoutCost` scales off `BaseHiringCost` rather than armor value.
3. **Optional Equipment-Free Hiring**:
   - Players can toggle **"Include Equipment"** in the Town Hire Screen to hire any recruit without starting gear, paying `BaseHiringCost * HiringCostMult` (which strips gear markup while retaining any veteran pending level-up surcharge).
4. **Zero-Serialization Save Compatibility & Dynamic Mod Support**:
   - Evaluates `onChangeAttributes()` and `BaseProperties` dynamically in a late load-order bucket (`>msu, >mod_reforged, >mod_hardened, >mod_backgrounds_and_events`) with zero custom save serialization.

---

## 2. Pillar 1: Tight-Margin Variance, Star Curve & Pending Level-Ups

```mermaid
flowchart LR
    A["Read onChangeAttributes()"] --> B["Soft-Compress Extreme Midpoints (S < -1.5 or S > 42)"]
    B --> C["Apply Linear Stat Roll Variance VarMult(S_adj) in [0.10x, 0.56x]"]
    C --> D["Filter ExcludedTalents (Keep <=1 Thematic Flaw)"]
    D --> E["Solve u in [0, 1] via Dynamic DP G_top3(u)"]
    E --> F["Roll Stars + Highborn Pending Levels (1..6)"]
```

### 2.1 Standard Stat Points (SSP) Evaluation
| Attribute | Base 0★ Roll (`Min..Max`, Avg) | SSP Weight ($w_i$) | Value of 1★ over 10 Lvls (`+5` pts) | Off-Role Negative Discount (Background Evaluation) |
| :--- | :---: | :---: | :---: | :--- |
| **Melee Skill (`MAtk`)** | `1..3` (`2.0`) | **1.50** | `+7.50 SSP` | `×0.35` if dedicated ranged (`RAtk ≥ +10, MAtk ≤ 0`) |
| **Melee Defense (`MDef`)** | `1..3` (`2.0`) | **1.50** | `+7.50 SSP` | `×0.35` if dedicated ranged (`RAtk ≥ +10, MAtk ≤ 0`) |
| **Hitpoints (`HP`)** | `2..4` (`3.0`) | **1.00** | `+5.00 SSP` | `×1.00` (`×0.65` only if glass-cannon archer `RAtk ≥ +20`) |
| **Resolve (`Bravery`)** | `2..4` (`3.0`) | **1.00** | `+5.00 SSP` | `×1.00` (universal survival stat) |
| **Fatigue (`Stamina`)** | `2..4` (`3.0`) | **1.00** | `+5.00 SSP` | `×1.00` (`×0.65` only if glass-cannon archer `RAtk ≥ +20`) |
| **Ranged Skill (`RAtk`)** | `2..4` (`3.0`) | **1.00** | `+5.00 SSP` | `×0.35` if melee-capable (`MAtk ≥ +5`) |
| **Initiative (`Ini`)** | `3..5` (`4.0`) | **0.75** | `+3.75 SSP` | `×0.40` (dumpable via heavy/fat-neutral builds) |
| **Ranged Defense (`RDef`)** | `2..4` (`3.0`) | **0.75** | `+3.75 SSP` | `×0.40` (secondary defense) |

- **Dual-Offense Discount**: When both `MAtk > 0` and `RAtk > 0`, the smaller positive offensive SSP term is discounted by **40%**.

### 2.2 Midpoint Outlier Compression & Linear Stat-Roll Variance (`onChangeAttributes`)
- **Outlier Compression**: `S_0 > +42.0 SSP` scales positive deltas to $\min(46.5,\; 42.0 + 0.12(S_0 - 42.0))$; `S_0 < -1.5 SSP` scales negative deltas to $\max(-3.0,\; -1.5 + 0.10(S_0 + 1.5))$.
- **Linear Roll Width**:
  $$\text{VarMult}(S_{\text{mid}}) = 0.52 - 0.42 \cdot \text{clamp}\!\left(\frac{S_{\text{mid}} - (-8.0)}{45.0 - (-8.0)},\; 0,\; 1\right)$$

### 2.3 Dynamic `G_top3(u)` Star Calibration (`balance_math.nut`)
- **Runtime Benchmark Anchor**: `TargetBackground` (`"militia_background"`, `StartSSP = +23.3`, `EndgameSSP = 41.9`) sets:
  $$E_{11,\text{target}}(S_{\text{adj}}) = 41.86 + 0.18 \cdot \big(S_{\text{adj}} - 23.30\big)$$
- **Star Count & Tier Curve**:
  - $u = 0.00$ (Highborn): $\mu_N = 0.50$, $\sigma_N = 0.45$, tiers `(96% 1★, 4% 2★, 0% 3★)`.
  - $u = 0.40$ (Militia): $\mu_N = 3.00$, tiers `(82% 1★, 18% 2★, 0% 3★)`.
  - $u = 1.00$ (Lowborn): $\mu_N = 6.80$, $\sigma_N = 0.42$, tiers `(5% 1★, 90% 2★, 5% 3★)`.

### 2.4 Highborn Pending Level-Ups (`1..6` Pending Levels)
- Any newly generated non-scenario recruit with `S_adj >= 33.5 SSP` rolls `1..6` pending level-ups (`Level 2..7`) with weights `28% / 26% / 20% / 13% / 8% / 5%` (`character_background.onAdded`), granting immediate `PerkPoints` and attribute `LevelUps` upon hiring.

---

## 3. Pillar 2: Stat-Driven Daily Wage & Signing Cost

### 3.1 Daily Wage Formula (`character_background.onUpdate`)
$$\text{StatDailyWage}(B_{\text{actor}}) = \max\!\Big(3,\; \text{round}\big(6.8 + 0.165 \cdot B_{\text{actor}}\big)\Big)$$

### 3.2 Base Hiring Cost, Pending Level-Up Surcharge & Equipped Cost
For a recruit at starting level $L$ ($N = L - 1$ pending level-ups):
$$\text{Level1StatCost} = \max\!\Big(20,\; 50.0 \cdot e^{0.030 \cdot B_{\text{actor}}}\Big)$$
$$\text{PendingLevelCost} = \left\lfloor 500 \cdot N^{1.5} \right\rfloor$$
$$\text{BaseHiringCost} = 10 \cdot \left\lceil \frac{\text{Level1StatCost} + \text{PendingLevelCost}}{10} \right\rceil$$
- Pending level-up surcharge matches Vanilla's exact `floor(500 * N^1.5)` curve (`+500c` for `+1`, `+1,414c` for `+2`, `+2,598c` for `+3`, `+4,000c` for `+4`, `+5,590c` for `+5`, `+7,348c` for `+6`), making high-level Highborn recruits a major crown investment (`~680c` to `~7,530c` before equipment, and `~3,500c` to `~12,500c` equipped).

---

## 4. Pillar 3: Hiring Recruits Without Equipment (UI & Backend)

```mermaid
sequenceDiagram
    participant UI as WorldTownScreenHireDialogModule (JS)
    participant Helper as UIDataHelper (Squirrel)
    participant Dialog as town_hire_dialog_module (Squirrel)
    participant Player as player / item_container (Squirrel)

    UI->>Dialog: queryHireInformation()
    Dialog->>Helper: convertEntityHireInformationToUIData(bro)
    Helper-->>UI: InitialMoneyCost (with gear) + NoEquipMoneyCost (no gear)
    Note over UI: User toggles "Include Equipment" checkbox OFF
    UI->>UI: Update roster cards, InitialMoneyCostsText & HireButton state
    UI->>Dialog: SQ.call("onHireRosterEntryWithoutEquipment", entityID)
    Dialog->>Player: Check Money >= NoEquipMoneyCost & Roster Space
    Dialog->>Player: Clear equipped & bag items; deduct NoEquipMoneyCost
    Dialog->>Player: Add to PlayerRoster & call bro.onHired()
    Dialog-->>UI: Updated Assets; remove entry from town roster
```

---

## 5. Repository File Structure

```text
mod_balanced_backgrounds/
├── README.md
├── AGENTS.md
├── PLAN.md
├── simulate_bros.py
├── scripts/
│   └── !mods_preload/
│       └── mod_balanced_backgrounds.nut
├── mod_balanced_backgrounds/
│   ├── config/
│   │   ├── params.nut
│   │   └── balance_math.nut
│   └── hooks/
│       ├── entity/tactical/player.nut
│       ├── scenarios/world/starting_scenario.nut
│       ├── skills/backgrounds/
│       │   ├── character_background.nut
│       │   └── companion_backgrounds.nut
│       ├── mods/mod_reforged/perk_groups.nut
│       └── ui/
│           ├── global/data_helper.nut
│           ├── screens/tooltip/tooltip_events.nut
│           └── screens/world/modules/world_town_screen/town_hire_dialog_module.nut
└── ui/
    └── mods/mod_balanced_backgrounds/
        ├── css/hire_dialog_module.css
        └── js/hire_dialog_module.js
```

---

## 6. Complete Per-Background Reference Table (All 138 Backgrounds)

### 6.1 Hireable, Origin & Event-Recruit Backgrounds (133 Backgrounds, Sorted Lowest $\to$ Highest Starting Budget)

| # | Src | Background | Script | Orig `S_0` | `VarMult` & Level-1 Roll Ranges | Excluded Talents | Adj `S_adj` | Talented Attrs `N` | Star Tiers (`1★/2★/3★`) | `E[★]` | Lvl-11 `Mean ± SD` (`P95`) | Pending Lvls | Base Wage | No-Gear Cost |
| :-: | :--- | :--- | :--- | :---: | :--- | :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 | Vanilla | **Cripple** | `cripple_background.nut` | `-35.2` | **`0.49×`** *(compressed)*: `HP 51..56, Res 33..37, Fat 92..97, Ini 101..105, MAtk 49..53, RAtk 34..39, MDef 1..4, RDef 1..4` | Keep `Ini` *(clear `HP`)* | `-4.6` | `6(100%)` | `5% / 92% / 3%` | **11.88★** | `34.4 ± 5.5` (`P95 43.8`) | `+0` | `6/d` | `50c` |
| 2 | Vanilla | **Cripple** | `cripple_southern_background.nut` | `-35.2` | **`0.49×`** *(compressed)*: `HP 51..56, Res 33..37, Fat 92..97, Ini 101..105, MAtk 49..53, RAtk 34..39, MDef 1..4, RDef 1..4` | Keep `Ini` *(clear `HP`)* | `-4.6` | `6(100%)` | `5% / 92% / 3%` | **11.88★** | `34.7 ± 5.6` (`P95 44.3`) | `+0` | `6/d` | `50c` |
| 3 | Vanilla | **Beggar** | `beggar_background.nut` | `-27.5` | **`0.48×`** *(compressed)*: `HP 52..56, Res 32..36, Fat 92..96, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `HP, Res` | `-3.0` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.5 ± 5.2` (`P95 45.1`) | `+0` | `6/d` | `50c` |
| 4 | Vanilla | **Beggar** | `beggar_southern_background.nut` | `-27.5` | **`0.48×`** *(compressed)*: `HP 52..56, Res 32..36, Fat 92..96, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `HP, Res` | `-3.0` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.6 ± 5.4` (`P95 45.3`) | `+0` | `6/d` | `50c` |
| 5 | Vanilla | **Historian** | `historian_background.nut` | `-18.5` | **`0.48×`** *(compressed)*: `HP 52..57, Res 33..37, Fat 92..96, Ini 103..107, MAtk 49..53, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `HP, Fat` | `-3.0` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.3 ± 5.4` (`P95 45.3`) | `+0` | `6/d` | `50c` |
| 6 | Vanilla | **Historian** | `historian_southern_background.nut` | `-18.5` | **`0.48×`** *(compressed)*: `HP 52..57, Res 33..37, Fat 92..96, Ini 103..107, MAtk 49..53, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `HP, Fat` | `-3.0` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.6 ± 5.4` (`P95 45.4`) | `+0` | `6/d` | `50c` |
| 7 | Vanilla | **Indebted** | `slave_background.nut` | `-14.0` | **`0.48×`** *(compressed)*: `HP 51..55, Res 32..37, Fat 93..97, Ini 102..106, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `HP, Res` | `-2.8` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.4 ± 5.4` (`P95 45.2`) | `+0` | `6/d` | `50c` |
| 8 | Vanilla | **Indebted** | `slave_southern_background.nut` | `-14.0` | **`0.48×`** *(compressed)*: `HP 49..53, Res 30..34, Fat 98..102, Ini 101..105, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `HP, Res` | `-2.6` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.5 ± 5.1` (`P95 44.9`) | `+0` | `6/d` | `50c` |
| 9 | XBE | **Cartographer** | `cartographer_background.nut` | `-12.5` | **`0.48×`** *(compressed)*: `HP 51..56, Res 33..37, Fat 92..96, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-2.5` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.9 ± 5.4` (`P95 46.0`) | `+0` | `6/d` | `50c` |
| 10 | Vanilla | **Servant** | `servant_background.nut` | `-12.4` | **`0.48×`** *(compressed)*: `HP 51..55, Res 31..35, Fat 91..95, Ini 105..110, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 2..5` | — | `-3.4` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `35.5 ± 5.5` (`P95 44.4`) | `+0` | `6/d` | `50c` |
| 11 | Vanilla | **Servant** | `servant_southern_background.nut` | `-12.4` | **`0.48×`** *(compressed)*: `HP 51..55, Res 31..35, Fat 91..95, Ini 105..110, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 2..5` | — | `-3.4` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `35.6 ± 5.4` (`P95 44.4`) | `+0` | `6/d` | `50c` |
| 12 | XBE | **Leper** | `leper_background.nut` | `-12.4` | **`0.48×`** *(compressed)*: `HP 63..68, Res 35..40, Fat 88..92, Ini 98..102, MAtk 48..52, RAtk 27..31, MDef 2..5, RDef 1..4` | Keep `HP` | `-3.0` | `6(100%)` | `5% / 92% / 3%` | **11.88★** | `36.1 ± 5.2` (`P95 44.9`) | `+0` | `6/d` | `50c` |
| 13 | Vanilla | **Indebted** | `slave_barbarian_background.nut` | `-6.7` | **`0.47×`** *(compressed)*: `HP 53..57, Res 28..33, Fat 98..102, Ini 100..104, MAtk 50..54, RAtk 35..39, MDef 0..3, RDef 0..3` | Clear `HP, Res` | `-2.2` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.7 ± 5.4` (`P95 45.7`) | `+0` | `6/d` | `50c` |
| 14 | Vanilla | **Eunuch** | `eunuch_background.nut` | `-6.5` | **`0.48×`** *(compressed)*: `HP 53..57, Res 31..35, Fat 93..97, Ini 101..105, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-2.6` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.6 ± 5.1` (`P95 45.3`) | `+0` | `6/d` | `50c` |
| 15 | Vanilla | **Eunuch** | `eunuch_southern_background.nut` | `-6.5` | **`0.48×`** *(compressed)*: `HP 53..57, Res 31..35, Fat 93..97, Ini 101..105, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-2.6` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `36.5 ± 5.3` (`P95 45.3`) | `+0` | `6/d` | `50c` |
| 16 | Vanilla | **Refugee** | `refugee_background.nut` | `-5.1` | **`0.47×`** *(compressed)*: `HP 48..53, Res 30..34, Fat 99..103, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 2..4` | — | `-1.1` | `6(21%) / 7(79%)` | `6% / 91% / 3%` | **13.38★** | `38.2 ± 5.5` (`P95 47.5`) | `+0` | `7/d` | `50c` |
| 17 | XBE | **Painter** | `painter_background.nut` | `-5.1` | **`0.47×`** *(compressed)*: `HP 49..53, Res 34..38, Fat 92..97, Ini 105..110, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-1.6` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `37.7 ± 5.4` (`P95 46.6`) | `+0` | `7/d` | `50c` |
| 18 | XBE | **Herbalist** | `herbalist_background.nut` | `-5.0` | **`0.48×`** *(compressed)*: `HP 53..57, Res 32..37, Fat 92..97, Ini 103..107, MAtk 49..53, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-2.5` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `37.0 ± 5.4` (`P95 45.5`) | `+0` | `6/d` | `50c` |
| 19 | Vanilla | **Minstrel** | `minstrel_background.nut` | `-4.6` | **`0.47×`** *(compressed)*: `HP 50..54, Res 40..45, Fat 85..89, Ini 105..110, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-1.6` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `37.4 ± 5.5` (`P95 46.4`) | `+0` | `7/d` | `50c` |
| 20 | Vanilla | **Tailor** | `tailor_background.nut` | `-4.6` | **`0.47×`** *(compressed)*: `HP 52..56, Res 33..37, Fat 90..94, Ini 105..110, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-2.1` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `37.3 ± 5.4` (`P95 46.6`) | `+0` | `6/d` | `50c` |
| 21 | Vanilla | **Tailor** | `tailor_southern_background.nut` | `-4.6` | **`0.47×`** *(compressed)*: `HP 52..56, Res 33..37, Fat 90..94, Ini 105..110, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-2.1` | `6(15%) / 7(85%)` | `5% / 92% / 3%` | **13.56★** | `37.2 ± 5.5` (`P95 46.4`) | `+0` | `6/d` | `50c` |
| 22 | Vanilla | **Monk** | `monk_background.nut` | `-1.5` | **`0.47×`**: `HP 53..57, Res 44..48, Fat 88..92, Ini 103..107, MAtk 45..49, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `-1.5` | `6(21%) / 7(79%)` | `6% / 91% / 3%` | **13.38★** | `38.0 ± 5.6` (`P95 47.4`) | `+0` | `7/d` | `50c` |
| 23 | Vanilla | **Peddler** | `peddler_background.nut` | `-1.5` | **`0.47×`**: `HP 53..57, Res 33..37, Fat 93..97, Ini 106..111, MAtk 40..45, RAtk 35..39, MDef 6..8, RDef 6..8` | — | `-1.5` | `6(21%) / 7(79%)` | `6% / 91% / 3%` | **13.38★** | `37.5 ± 5.6` (`P95 46.6`) | `+0` | `7/d` | `50c` |
| 24 | Vanilla | **Peddler** | `peddler_southern_background.nut` | `-1.5` | **`0.47×`**: `HP 53..57, Res 33..37, Fat 93..97, Ini 106..111, MAtk 40..45, RAtk 35..39, MDef 6..8, RDef 6..8` | — | `-1.5` | `6(21%) / 7(79%)` | `6% / 91% / 3%` | **13.38★** | `37.6 ± 5.7` (`P95 47.4`) | `+0` | `7/d` | `50c` |
| 25 | Vanilla | **Apprentice** | `apprentice_background.nut` | `+0.0` | **`0.46×`**: `HP 53..57, Res 33..37, Fat 93..97, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+0.0` | `6(52%) / 7(48%)` | `11% / 86% / 3%` | **12.44★** | `38.4 ± 5.7` (`P95 47.8`) | `+0` | `7/d` | `50c` |
| 26 | XBE | **Cook** | `cook_background.nut` | `+1.3` | **`0.45×`**: `HP 64..68, Res 28..32, Fat 91..96, Ini 99..103, MAtk 50..54, RAtk 33..37, MDef 1..4, RDef 1..4` | Clear `Fat` | `+1.3` | `5(2%) / 6(85%) / 7(13%)` | `18% / 80% / 2%` | **11.24★** | `38.0 ± 5.9` (`P95 47.8`) | `+0` | `7/d` | `60c` |
| 27 | Vanilla | **Killer on the Run** | `killer_on_the_run_background.nut` | `+1.4` | **`0.45×`**: `HP 53..57, Res 28..32, Fat 93..97, Ini 105..110, MAtk 52..56, RAtk 37..42, MDef 1..4, RDef 1..4` | — | `+1.4` | `5(3%) / 6(87%) / 7(10%)` | `19% / 78% / 3%` | **11.17★** | `38.5 ± 5.9` (`P95 48.5`) | `+0` | `7/d` | `60c` |
| 28 | Vanilla | **Daytaler** | `daytaler_background.nut` | `+1.5` | **`0.44×`**: `HP 53..57, Res 33..37, Fat 94..99, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+1.5` | `5(4%) / 6(89%) / 7(7%)` | `20% / 77% / 3%` | **11.03★** | `38.4 ± 6.0` (`P95 48.3`) | `+0` | `7/d` | `60c` |
| 29 | Vanilla | **Daytaler** | `daytaler_southern_background.nut` | `+1.5` | **`0.44×`**: `HP 53..57, Res 33..37, Fat 94..99, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+1.5` | `5(4%) / 6(89%) / 7(7%)` | `20% / 77% / 3%` | **11.03★** | `38.2 ± 6.2` (`P95 48.4`) | `+0` | `7/d` | `60c` |
| 30 | XBE | **Cobbler** | `cobbler_background.nut` | `+3.0` | **`0.43×`**: `HP 53..57, Res 33..37, Fat 93..97, Ini 103..107, MAtk 52..56, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `Res` | `+3.0` | `5(17%) / 6(81%) / 7(2%)` | `26% / 72% / 2%` | **10.30★** | `38.8 ± 6.2` (`P95 48.9`) | `+0` | `7/d` | `60c` |
| 31 | XBE | **Locksmith** | `locksmith_background.nut` | `+4.5` | **`0.42×`**: `HP 53..57, Res 33..37, Fat 93..97, Ini 107..111, MAtk 51..55, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+4.5` | `5(45%) / 6(55%)` | `31% / 67% / 2%` | **9.49★** | `38.7 ± 6.4` (`P95 48.8`) | `+0` | `8/d` | `60c` |
| 32 | Vanilla | **Bowyer** | `bowyer_background.nut` | `+5.0` | **`0.42×`**: `HP 53..57, Res 30..35, Fat 90..95, Ini 103..107, MAtk 50..54, RAtk 45..49, MDef 1..4, RDef 1..4` | Keep `MAtk` | `+5.0` | `5(2%) / 6(98%)` | `18% / 80% / 2%` | **11.00★** | `39.3 ± 5.3` (`P95 47.6`) | `+0` | `8/d` | `60c` |
| 33 | Vanilla | **Mason** | `mason_background.nut` | `+5.0` | **`0.42×`**: `HP 53..57, Res 33..37, Fat 98..102, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+5.0` | `5(63%) / 6(37%)` | `33% / 65% / 2%` | **9.08★** | `38.9 ± 6.8` (`P95 50.0`) | `+0` | `8/d` | `60c` |
| 34 | Vanilla | **Vagabond** | `vagabond_background.nut` | `+5.0` | **`0.42×`**: `HP 51..56, Res 27..31, Fat 105..110, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+5.0` | `5(63%) / 6(37%)` | `33% / 65% / 2%` | **9.08★** | `38.8 ± 6.6` (`P95 49.8`) | `+0` | `8/d` | `60c` |
| 35 | XBE | **Gardener** | `gardener_background.nut` | `+5.5` | **`0.41×`**: `HP 53..57, Res 30..34, Fat 97..101, Ini 107..111, MAtk 51..55, RAtk 35..39, MDef 1..4, RDef 1..4` | Clear `Res` | `+5.5` | `4(1%) / 5(69%) / 6(30%)` | `35% / 64% / 1%` | **8.78★** | `38.2 ± 6.7` (`P95 49.0`) | `+0` | `8/d` | `60c` |
| 36 | Vanilla | **Deserter** | `deserter_background.nut` | `+6.1` | **`0.41×`**: `HP 53..57, Res 20..25, Fat 93..97, Ini 103..107, MAtk 54..60, RAtk 38..43, MDef 5..8, RDef 5..8` | Keep `Res` | `+6.1` | `4(2%) / 5(85%) / 6(13%)` | `38% / 60% / 2%` | **8.38★** | `39.1 ± 7.2` (`P95 50.3`) | `+0..+1` | `8/d` | `70..570c` |
| 37 | Vanilla | **Bastard** | `bastard_background.nut` | `+6.2` | **`0.41×`**: `HP 53..57, Res 28..32, Fat 93..97, Ini 103..107, MAtk 54..65, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+6.2` | `4(2%) / 5(81%) / 6(17%)` | `37% / 61% / 2%` | **8.50★** | `39.1 ± 8.1` (`P95 52.0`) | `+0..+2` | `8/d` | `70..1480c` |
| 38 | Vanilla | **Juggler** | `juggler_background.nut` | `+6.2` | **`0.41×`**: `HP 48..52, Res 33..37, Fat 93..97, Ini 114..118, MAtk 50..54, RAtk 38..42, MDef 1..4, RDef 1..4` | — | `+6.2` | `4(2%) / 5(81%) / 6(17%)` | `37% / 61% / 2%` | **8.50★** | `38.9 ± 6.7` (`P95 50.1`) | `+0` | `8/d` | `70c` |
| 39 | Vanilla | **Juggler** | `juggler_southern_background.nut` | `+6.2` | **`0.41×`**: `HP 48..52, Res 33..37, Fat 93..97, Ini 114..118, MAtk 50..54, RAtk 38..42, MDef 1..4, RDef 1..4` | — | `+6.2` | `4(2%) / 5(81%) / 6(17%)` | `37% / 61% / 2%` | **8.50★** | `38.7 ± 7.0` (`P95 50.3`) | `+0` | `8/d` | `70c` |
| 40 | XBE | **Atilliator** | `atilliator_background.nut` | `+6.5` | **`0.41×`**: `HP 53..57, Res 30..35, Fat 90..95, Ini 103..107, MAtk 50..54, RAtk 46..51, MDef 1..4, RDef 1..4` | Keep `MAtk` | `+6.5` | `5(29%) / 6(71%)` | `28% / 70% / 2%` | **9.94★** | `39.6 ± 5.8` (`P95 48.9`) | `+0` | `8/d` | `70c` |
| 41 | XBE | **Carpenter** | `carpenter_background.nut` | `+6.5` | **`0.41×`**: `HP 57..61, Res 33..37, Fat 91..95, Ini 103..107, MAtk 53..57, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+6.5` | `4(2%) / 5(81%) / 6(17%)` | `37% / 61% / 2%` | **8.50★** | `39.3 ± 6.7` (`P95 49.9`) | `+0` | `8/d` | `70c` |
| 42 | Vanilla | **Ratcatcher** | `ratcatcher_background.nut` | `+7.4` | **`0.40×`**: `HP 48..52, Res 33..37, Fat 93..97, Ini 120..123, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+7.4` | `4(5%) / 5(88%) / 6(7%)` | `41% / 57% / 2%` | **8.08★** | `39.1 ± 6.8` (`P95 50.4`) | `+0` | `8/d` | `70c` |
| 43 | Vanilla | **Disowned Noble** | `disowned_noble_background.nut` | `+7.5` | **`0.40×`**: `HP 53..57, Res 30..33, Fat 86..89, Ini 103..107, MAtk 59..63, RAtk 40..43, MDef 3..5, RDef 2..3` | — | `+7.5` | `4(5%) / 5(88%) / 6(7%)` | `41% / 57% / 2%` | **8.08★** | `39.3 ± 6.7` (`P95 50.3`) | `+0..+2` | `8/d` | `70..1480c` |
| 44 | XBE | **Hangman** | `hangman_background.nut` | `+7.7` | **`0.40×`**: `HP 57..61, Res 37..41, Fat 93..97, Ini 102..106, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+7.7` | `4(7%) / 5(88%) / 6(5%)` | `42% / 56% / 2%` | **7.97★** | `39.1 ± 6.7` (`P95 49.9`) | `+0` | `8/d` | `70c` |
| 45 | Vanilla | **Miller** | `miller_background.nut` | `+8.0` | **`0.39×`**: `HP 55..58, Res 33..37, Fat 100..103, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+8.0` | `4(7%) / 5(88%) / 6(5%)` | `42% / 56% / 2%` | **7.97★** | `39.7 ± 6.8` (`P95 50.5`) | `+0` | `8/d` | `70c` |
| 46 | XBE | **Surgeon** | `surgeon_background.nut` | `+10.0` | **`0.38×`**: `HP 53..57, Res 37..41, Fat 93..97, Ini 103..107, MAtk 54..58, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+10.0` | `4(24%) / 5(75%) / 6(1%)` | `47% / 51% / 2%` | **7.39★** | `40.5 ± 6.9` (`P95 51.8`) | `+0` | `8/d` | `70c` |
| 47 | Vanilla | **Miner** | `miner_background.nut` | `+10.2` | **`0.38×`**: `HP 63..67, Res 40..43, Fat 83..87, Ini 103..107, MAtk 53..56, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+10.2` | `4(31%) / 5(68%) / 6(1%)` | `49% / 50% / 1%` | **7.14★** | `39.7 ± 6.7` (`P95 50.8`) | `+0` | `8/d` | `70c` |
| 48 | Vanilla | **Pimp** | `pimp_background.nut` | `+10.2` | **`0.38×`**: `HP 53..57, Res 38..42, Fat 93..97, Ini 107..110, MAtk 45..49, RAtk 35..39, MDef 6..8, RDef 6..8` | — | `+10.2` | `4(31%) / 5(68%) / 6(1%)` | `49% / 50% / 1%` | **7.14★** | `39.3 ± 7.0` (`P95 50.6`) | `+0` | `8/d` | `70c` |
| 49 | Vanilla | **Belly Dancer** | `belly_dancer_background.nut` | `+10.5` | **`0.37×`**: `HP 48..52, Res 28..32, Fat 88..92, Ini 113..117, MAtk 60..64, RAtk 40..44, MDef 2..3, RDef 2..3` | Clear `HP, Fat, RDef, Res` | `+10.5` | `4(31%) / 5(68%) / 6(1%)` | `49% / 50% / 1%` | **7.14★** | `39.8 ± 6.9` (`P95 51.5`) | `+0` | `9/d` | `70c` |
| 50 | XBE | **Drifter** | `drifter_background.nut` | `+10.9` | **`0.37×`**: `HP 52..56, Res 33..37, Fat 100..104, Ini 108..112, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 3..5` | — | `+10.9` | `4(39%) / 5(61%)` | `50% / 49% / 1%` | **6.96★** | `39.4 ± 6.8` (`P95 50.5`) | `+0` | `9/d` | `70c` |
| 51 | Vanilla | **Shepherd** | `shepherd_background.nut` | `+11.0` | **`0.37×`**: `HP 53..57, Res 36..39, Fat 96..99, Ini 103..107, MAtk 50..54, RAtk 41..45, MDef 2..3, RDef 2..3` | — | `+11.0` | `4(39%) / 5(61%)` | `50% / 49% / 1%` | **6.96★** | `39.7 ± 6.8` (`P95 50.9`) | `+0` | `9/d` | `70c` |
| 52 | Vanilla | **Shepherd** | `shepherd_southern_background.nut` | `+11.0` | **`0.37×`**: `HP 53..57, Res 36..39, Fat 96..99, Ini 103..107, MAtk 50..54, RAtk 41..45, MDef 2..3, RDef 2..3` | — | `+11.0` | `4(39%) / 5(61%)` | `50% / 49% / 1%` | **6.96★** | `39.8 ± 6.8` (`P95 50.9`) | `+0` | `9/d` | `70c` |
| 53 | XBE | **Blacksmith** | `blacksmith_background.nut` | `+11.0` | **`0.37×`**: `HP 57..61, Res 33..37, Fat 97..101, Ini 103..107, MAtk 52..56, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+11.0` | `4(39%) / 5(61%)` | `50% / 49% / 1%` | **6.96★** | `40.1 ± 6.9` (`P95 51.4`) | `+0` | `9/d` | `70c` |
| 54 | Vanilla | **Fisherman** | `fisherman_background.nut` | `+11.9` | **`0.36×`**: `HP 56..59, Res 36..39, Fat 98..102, Ini 106..109, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+11.9` | `4(56%) / 5(44%)` | `52% / 46% / 2%` | **6.66★** | `40.4 ± 7.1` (`P95 52.2`) | `+0` | `9/d` | `80c` |
| 55 | Vanilla | **Fisherman** | `fisherman_southern_background.nut` | `+11.9` | **`0.36×`**: `HP 56..59, Res 36..39, Fat 98..102, Ini 106..109, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+11.9` | `4(56%) / 5(44%)` | `52% / 46% / 2%` | **6.66★** | `40.1 ± 7.0` (`P95 51.9`) | `+0` | `9/d` | `80c` |
| 56 | Vanilla | **Flagellant** | `flagellant_background.nut` | `+12.0` | **`0.36×`**: `HP 46..49, Res 45..49, Fat 101..104, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+12.0` | `4(56%) / 5(44%)` | `52% / 46% / 2%` | **6.66★** | `40.4 ± 7.2` (`P95 52.8`) | `+0` | `9/d` | `80c` |
| 57 | Vanilla | **Butcher** | `butcher_background.nut` | `+12.2` | **`0.36×`**: `HP 55..59, Res 39..43, Fat 95..99, Ini 103..107, MAtk 53..56, RAtk 34..37, MDef 2..3, RDef 2..3` | Keep `RAtk` | `+12.2` | `3(1%) / 4(63%) / 5(36%)` | `54% / 45% / 1%` | **6.39★** | `40.2 ± 6.9` (`P95 51.6`) | `+0` | `9/d` | `80c` |
| 58 | Vanilla | **Butcher** | `butcher_southern_background.nut` | `+12.2` | **`0.36×`**: `HP 55..59, Res 39..43, Fat 95..99, Ini 103..107, MAtk 53..56, RAtk 34..37, MDef 2..3, RDef 2..3` | Keep `RAtk` | `+12.2` | `3(1%) / 4(63%) / 5(36%)` | `54% / 45% / 1%` | **6.39★** | `40.1 ± 6.9` (`P95 51.6`) | `+0` | `9/d` | `80c` |
| 59 | XBE | **Torturer** | `torturer_background.nut` | `+12.6` | **`0.36×`**: `HP 61..64, Res 33..37, Fat 96..99, Ini 103..107, MAtk 54..57, RAtk 35..39, MDef 0..2, RDef 0..2` | — | `+12.6` | `3(1%) / 4(63%) / 5(36%)` | `54% / 45% / 1%` | **6.39★** | `39.7 ± 6.8` (`P95 50.7`) | `+0` | `9/d` | `80c` |
| 60 | XBE | **Fletcher** | `fletcher_background.nut` | `+13.1` | **`0.35×`**: `HP 51..55, Res 31..35, Fat 93..97, Ini 111..114, MAtk 50..54, RAtk 47..50, MDef 2..3, RDef 2..3` | Clear `HP, Res` | `+13.1` | `3(1%) / 4(71%) / 5(28%)` | `55% / 44% / 1%` | **6.23★** | `40.9 ± 6.8` (`P95 51.8`) | `+0` | `9/d` | `80c` |
| 61 | Vanilla | **Gravedigger** | `gravedigger_background.nut` | `+13.2` | **`0.35×`**: `HP 55..59, Res 39..43, Fat 99..103, Ini 101..104, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+13.2` | `3(1%) / 4(77%) / 5(22%)` | `56% / 43% / 1%` | **6.10★** | `40.3 ± 6.8` (`P95 51.8`) | `+0` | `9/d` | `80c` |
| 62 | XBE | **Druid** | `druid_background.nut` | `+13.5` | **`0.35×`**: `HP 58..62, Res 39..43, Fat 96..99, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+13.5` | `3(1%) / 4(77%) / 5(22%)` | `56% / 43% / 1%` | **6.10★** | `40.1 ± 6.8` (`P95 51.9`) | `+0..+1` | `9/d` | `80..580c` |
| 63 | XBE | **Dissenter** | `dissenter_background.nut` | `+14.5` | **`0.34×`**: `HP 53..57, Res 52..56, Fat 93..97, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef -1..0, RDef 2..3` | — | `+14.5` | `3(3%) / 4(85%) / 5(12%)` | `59% / 40% / 1%` | **5.81★** | `40.9 ± 7.0` (`P95 52.9`) | `+0` | `9/d` | `80c` |
| 64 | Vanilla | **Poacher** | `poacher_background.nut` | `+14.9` | **`0.34×`**: `HP 53..57, Res 33..37, Fat 95..98, Ini 105..109, MAtk 51..55, RAtk 46..50, MDef 2..3, RDef 2..3` | — | `+14.9` | `3(4%) / 4(87%) / 5(9%)` | `60% / 39% / 1%` | **5.71★** | `40.7 ± 6.7` (`P95 52.2`) | `+0` | `9/d` | `80c` |
| 65 | XBE | **Con Artist** | `con_artist_background.nut` | `+15.4` | **`0.33×`**: `HP 53..57, Res 33..37, Fat 93..97, Ini 108..112, MAtk 54..58, RAtk 37..41, MDef 4..5, RDef 4..5` | — | `+15.4` | `3(8%) / 4(87%) / 5(5%)` | `63% / 37% / 0%` | **5.44★** | `40.0 ± 6.6` (`P95 51.3`) | `+0` | `9/d` | `80c` |
| 66 | Vanilla | **Cultist** | `cultist_background.nut` | `+15.5` | **`0.33×`**: `HP 53..57, Res 46..49, Fat 96..100, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+15.5` | `3(8%) / 4(87%) / 5(5%)` | `63% / 37% / 0%` | **5.44★** | `40.3 ± 6.6` (`P95 52.0`) | `+0` | `9/d` | `80c` |
| 67 | Vanilla | **Caravan Hand** | `caravan_hand_background.nut` | `+16.0` | **`0.33×`**: `HP 57..61, Res 36..40, Fat 99..103, Ini 103..107, MAtk 52..56, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+16.0` | `3(11%) / 4(86%) / 5(3%)` | `64% / 35% / 1%` | **5.37★** | `40.8 ± 6.8` (`P95 52.9`) | `+0` | `9/d` | `90c` |
| 68 | Vanilla | **Caravan Hand** | `caravan_hand_southern_background.nut` | `+16.0` | **`0.33×`**: `HP 57..61, Res 36..40, Fat 99..103, Ini 103..107, MAtk 52..56, RAtk 35..39, MDef 2..3, RDef 2..3` | — | `+16.0` | `3(11%) / 4(86%) / 5(3%)` | `64% / 35% / 1%` | **5.37★** | `40.6 ± 7.0` (`P95 52.3`) | `+0` | `9/d` | `90c` |
| 69 | XBE | **Barkeep** | `barkeep_background.nut` | `+16.0` | **`0.33×`**: `HP 61..64, Res 33..37, Fat 97..101, Ini 98..102, MAtk 52..56, RAtk 35..39, MDef 4..5, RDef 2..3` | — | `+16.0` | `3(11%) / 4(86%) / 5(3%)` | `64% / 35% / 1%` | **5.37★** | `40.5 ± 6.7` (`P95 52.2`) | `+0` | `9/d` | `90c` |
| 70 | XBE | **Roofer** | `roofer_background.nut` | `+16.1` | **`0.33×`**: `HP 55..59, Res 33..37, Fat 101..104, Ini 100..104, MAtk 50..54, RAtk 35..39, MDef 7..8, RDef 2..3` | — | `+16.1` | `3(11%) / 4(86%) / 5(3%)` | `64% / 35% / 1%` | **5.37★** | `40.5 ± 6.8` (`P95 52.4`) | `+0` | `9/d` | `90c` |
| 71 | Vanilla | **Graverobber** | `graverobber_background.nut` | `+16.4` | **`0.33×`**: `HP 53..57, Res 40..43, Fat 98..102, Ini 105..109, MAtk 52..55, RAtk 35..39, MDef 2..4, RDef 2..4` | — | `+16.4` | `3(11%) / 4(86%) / 5(3%)` | `64% / 35% / 1%` | **5.37★** | `40.8 ± 6.8` (`P95 52.9`) | `+0` | `10/d` | `90c` |
| 72 | Vanilla | **Houndmaster** | `houndmaster_background.nut` | `+16.4` | **`0.33×`**: `HP 56..59, Res 38..42, Fat 96..99, Ini 106..109, MAtk 50..54, RAtk 35..39, MDef 5..6, RDef 2..3` | — | `+16.4` | `3(11%) / 4(86%) / 5(3%)` | `64% / 35% / 1%` | **5.37★** | `41.0 ± 6.7` (`P95 52.3`) | `+0` | `10/d` | `90c` |
| 73 | XBE | **Arbalester** | `arbalester_background.nut` | `+16.6` | **`0.32×`**: `HP 51..54, Res 33..37, Fat 97..101, Ini 103..107, MAtk 50..54, RAtk 49..53, MDef 2..3, RDef 3..5` | Keep `MAtk` *(clear `MDef`)* | `+16.6` | `3(3%) / 4(85%) / 5(12%)` | `59% / 40% / 1%` | **5.81★** | `41.5 ± 6.3` (`P95 52.1`) | `+0..+2` | `10/d` | `90..1500c` |
| 74 | Vanilla | **Gambler** | `gambler_background.nut` | `+18.0` | **`0.31×`**: `HP 51..55, Res 45..49, Fat 88..91, Ini 114..118, MAtk 50..54, RAtk 35..39, MDef 3..4, RDef 7..8` | — | `+18.0` | `3(33%) / 4(66%) / 5(1%)` | `69% / 30% / 1%` | **4.86★** | `40.8 ± 6.7` (`P95 52.6`) | `+0` | `10/d` | `90c` |
| 75 | Vanilla | **Gambler** | `gambler_southern_background.nut` | `+18.0` | **`0.31×`**: `HP 51..55, Res 45..49, Fat 88..91, Ini 114..118, MAtk 50..54, RAtk 35..39, MDef 3..4, RDef 7..8` | — | `+18.0` | `3(33%) / 4(66%) / 5(1%)` | `69% / 30% / 1%` | **4.86★** | `40.7 ± 6.7` (`P95 52.4`) | `+0` | `10/d` | `90c` |
| 76 | XBE | **Falconer** | `falconer_background.nut` | `+18.0` | **`0.31×`**: `HP 50..54, Res 33..37, Fat 93..97, Ini 120..124, MAtk 50..54, RAtk 44..48, MDef -1..1, RDef 6..7` | — | `+18.0` | `3(33%) / 4(66%) / 5(1%)` | `69% / 30% / 1%` | **4.86★** | `41.3 ± 6.8` (`P95 53.0`) | `+0` | `10/d` | `90c` |
| 77 | Vanilla | **Messenger** | `messenger_background.nut` | `+18.8` | **`0.31×`**: `HP 53..57, Res 36..39, Fat 106..109, Ini 103..107, MAtk 50..54, RAtk 35..39, MDef 3..4, RDef 5..6` | — | `+18.8` | `3(41%) / 4(59%)` | `70% / 29% / 1%` | **4.70★** | `41.2 ± 6.5` (`P95 53.2`) | `+0` | `10/d` | `90c` |
| 78 | Vanilla | **Retired Soldier** | `retired_soldier_background.nut` | `+20.1` | **`0.30×`**: `HP 41..44, Res 45..48, Fat 84..86, Ini 96..99, MAtk 62..65, RAtk 38..41, MDef 8..10, RDef 8..10` | — | `+20.1` | `2(1%) / 3(65%) / 4(34%)` | `74% / 25% / 1%` | **4.23★** | `41.1 ± 6.1` (`P95 51.5`) | `+1..+2` | `10/d` | `600..1510c` |
| 79 | Vanilla | **Anatomist** | `anatomist_background.nut` | `+20.5` | **`0.29×`**: `HP 50..52, Res 44..46, Fat 91..94, Ini 104..106, MAtk 54..64, RAtk 45..47, MDef 2..4, RDef 2..4` | — | `+20.5` | `2(1%) / 3(65%) / 4(34%)` | `74% / 25% / 1%` | **4.23★** | `42.2 ± 7.1` (`P95 54.4`) | `+0` | `10/d` | `100c` |
| 80 | XBE | **Town Watchman** | `town_watchman_background.nut` | `+20.8` | **`0.29×`**: `HP 55..58, Res 35..37, Fat 99..101, Ini 106..109, MAtk 54..60, RAtk 42..45, MDef 2..3, RDef 2..3` | — | `+20.8` | `2(1%) / 3(72%) / 4(27%)` | `76% / 24% / 0%` | **4.04★** | `41.4 ± 6.0` (`P95 51.9`) | `+0` | `10/d` | `100c` |
| 81 | XBE | **Myrmidon** | `myrmidon_background.nut` | `+21.3` | **`0.29×`**: `HP 58..60, Res 30..32, Fat 98..100, Ini 107..109, MAtk 54..60, RAtk 43..45, MDef 3..5, RDef 3..5` | — | `+21.3` | `2(1%) / 3(78%) / 4(21%)` | `77% / 23% / 0%` | **3.94★** | `41.6 ± 5.8` (`P95 51.8`) | `+0..+2` | `10/d` | `100..1510c` |
| 82 | XBE | **Pirate** | `pirate_background.nut` | `+21.5` | **`0.29×`**: `HP 54..56, Res 32..35, Fat 99..101, Ini 109..111, MAtk 54..59, RAtk 36..38, MDef 5..6, RDef 6..7` | — | `+21.5` | `2(1%) / 3(78%) / 4(21%)` | `77% / 23% / 0%` | **3.94★** | `41.4 ± 5.8` (`P95 52.0`) | `+1..+3` | `10/d` | `600..2700c` |
| 83 | Vanilla | **Witchhunter** | `witchhunter_background.nut` | `+22.5` | **`0.28×`**: `HP 54..56, Res 45..47, Fat 94..96, Ini 104..106, MAtk 51..53, RAtk 47..50, MDef 2..3, RDef 2..3` | — | `+22.5` | `2(5%) / 3(86%) / 4(9%)` | `81% / 19% / 0%` | **3.62★** | `41.9 ± 5.0` (`P95 50.9`) | `+0..+2` | `11/d` | `100..1520c` |
| 84 | XBE | **Master Archer** | `master_archer_background.nut` | `+22.8` | **`0.28×`**: `HP 38..40, Res 38..40, Fat 85..88, Ini 114..116, MAtk 41..44, RAtk 66..68, MDef -3..-2, RDef 8..10` | Keep `MAtk` *(clear `MDef`)* | `+22.8` | `2(1%) / 3(78%) / 4(21%)` | `77% / 23% / 0%` | **3.94★** | `41.6 ± 4.8` (`P95 50.4`) | `+2..+4` | `11/d` | `1520..4100c` |
| 85 | Vanilla | **Militia** | `militia_background.nut` | `+23.3` | **`0.27×`**: `HP 54..56, Res 38..40, Fat 98..100, Ini 104..106, MAtk 54..60, RAtk 41..44, MDef 4..5, RDef 4..5` | — | `+23.3` | `2(6%) / 3(88%) / 4(6%)` | `82% / 18% / 0%` | **3.54★** | `42.1 ± 5.5` (`P95 51.9`) | `+0..+1` | `11/d` | `110..610c` |
| 86 | Vanilla | **Farmhand** | `farmhand_background.nut` | `+23.5` | **`0.27×`**: `HP 65..67, Res 31..34, Fat 109..111, Ini 104..106, MAtk 51..53, RAtk 36..38, MDef 2..3, RDef 2..3` | — | `+23.5` | `2(9%) / 3(86%) / 4(5%)` | `82% / 18% / 0%` | **3.49★** | `42.1 ± 5.2` (`P95 51.6`) | `+0` | `11/d` | `110c` |
| 87 | Vanilla | **Companion** *(Origin)* | `companion_ranged_background.nut` | `+24.0` | **`0.27×`**: `HP 54..56, Res 39..41, Fat 94..96, Ini 109..111, MAtk 53..56, RAtk 49..51, MDef 2..3, RDef 2..3` | Keep `MAtk` *(clear `HP, MDef`)* | `+24.0` | `2(5%) / 3(86%) / 4(9%)` | `81% / 19% / 0%` | **3.62★** | `41.8 ± 5.0` (`P95 50.8`) | `+0` | `11/d` | `110c` |
| 88 | Vanilla | **Companion** *(Origin)* | `companion_ranged_southern_background.nut` | `+24.0` | **`0.27×`**: `HP 54..56, Res 39..41, Fat 94..96, Ini 109..111, MAtk 53..56, RAtk 49..51, MDef 2..3, RDef 2..3` | Keep `MAtk` *(clear `HP, MDef`)* | `+24.0` | `2(5%) / 3(86%) / 4(9%)` | `81% / 19% / 0%` | **3.62★** | `41.7 ± 4.7` (`P95 50.5`) | `+0` | `11/d` | `110c` |
| 89 | Vanilla | **Thief** | `thief_background.nut` | `+25.4` | **`0.26×`**: `HP 54..56, Res 36..39, Fat 94..96, Ini 115..117, MAtk 51..53, RAtk 36..38, MDef 8..10, RDef 8..10` | — | `+25.4` | `2(27%) / 3(72%) / 4(1%)` | `84% / 16% / 0%` | **3.18★** | `42.2 ± 5.7` (`P95 52.6`) | `+0` | `11/d` | `110c` |
| 90 | Vanilla | **Thief** | `thief_southern_background.nut` | `+25.4` | **`0.26×`**: `HP 54..56, Res 36..39, Fat 94..96, Ini 115..117, MAtk 51..53, RAtk 36..38, MDef 8..10, RDef 8..10` | — | `+25.4` | `2(27%) / 3(72%) / 4(1%)` | `84% / 16% / 0%` | **3.18★** | `42.3 ± 5.5` (`P95 51.9`) | `+0` | `11/d` | `110c` |
| 91 | Vanilla | **Manhunter** | `manhunter_background.nut` | `+25.7` | **`0.25×`**: `HP 56..59, Res 40..42, Fat 98..100, Ini 108..110, MAtk 54..60, RAtk 36..38, MDef 4..5, RDef 1..2` | — | `+25.7` | `2(34%) / 3(65%) / 4(1%)` | `84% / 16% / 0%` | **3.10★** | `42.1 ± 6.2` (`P95 53.0`) | `+0` | `11/d` | `110c` |
| 92 | Vanilla | **Brawler** | `brawler_background.nut` | `+26.6` | **`0.25×`**: `HP 61..64, Res 40..42, Fat 101..104, Ini 106..109, MAtk 53..56, RAtk 36..38, MDef 2..3, RDef 2..3` | Keep `RAtk` | `+26.6` | `2(42%) / 3(58%)` | `84% / 16% / 0%` | **2.99★** | `42.4 ± 5.7` (`P95 52.9`) | `+0` | `11/d` | `120c` |
| 93 | Vanilla | **Nomad** | `nomad_ranged_background.nut` | `+27.7` | **`0.24×`**: `HP 54..56, Res 32..35, Fat 95..97, Ini 104..106, MAtk 54..58, RAtk 50..53, MDef 6..7, RDef 7..9` | — | `+27.7` | `2(58%) / 3(42%)` | `85% / 15% / 0%` | **2.78★** | `42.7 ± 5.6` (`P95 52.9`) | `+1..+3` | `11/d` | `620..2720c` |
| 94 | Vanilla | **Lumberjack** | `lumberjack_background.nut` | `+28.0` | **`0.23×`**: `HP 64..66, Res 36..39, Fat 106..109, Ini 101..104, MAtk 53..56, RAtk 36..38, MDef 2..3, RDef 2..3` | — | `+28.0` | `2(58%) / 3(42%)` | `85% / 15% / 0%` | **2.78★** | `42.8 ± 5.6` (`P95 53.2`) | `+0` | `11/d` | `120c` |
| 95 | XBE | **Skirmisher** | `skirmisher_background.nut` | `+28.1` | **`0.23×`**: `HP 51..54, Res 32..34, Fat 101..103, Ini 114..116, MAtk 54..60, RAtk 47..49, MDef 3..4, RDef 3..5` | Clear `Res` | `+28.1` | `2(58%) / 3(42%)` | `85% / 15% / 0%` | **2.78★** | `42.9 ± 5.6` (`P95 52.7`) | `+0..+1` | `11/d` | `120..620c` |
| 96 | Vanilla | **Nomad** | `nomad_background.nut` | `+29.9` | **`0.22×`**: `HP 54..56, Res 32..35, Fat 95..97, Ini 104..106, MAtk 62..64, RAtk 38..41, MDef 7..9, RDef 7..9` | — | `+29.9` | `1(2%) / 2(77%) / 3(21%)` | `86% / 14% / 0%` | **2.50★** | `43.3 ± 5.0` (`P95 52.4`) | `+1..+3` | `12/d` | `630..2730c` |
| 97 | Vanilla | **Raider** | `raider_background.nut` | `+29.9` | **`0.22×`**: `HP 54..56, Res 32..35, Fat 95..97, Ini 104..106, MAtk 62..64, RAtk 38..41, MDef 7..9, RDef 7..9` | — | `+29.9` | `1(2%) / 2(77%) / 3(21%)` | `86% / 14% / 0%` | **2.50★** | `43.3 ± 5.1` (`P95 52.5`) | `+1..+3` | `12/d` | `630..2730c` |
| 98 | Vanilla | **Hunter** | `hunter_background.nut` | `+30.0` | **`0.22×`**: `HP 54..56, Res 36..39, Fat 100..102, Ini 106..109, MAtk 51..53, RAtk 54..57, MDef 2..3, RDef 3..5` | — | `+30.0` | `1(2%) / 2(82%) / 3(16%)` | `87% / 13% / 0%` | **2.42★** | `43.1 ± 4.7` (`P95 51.6`) | `+0..+1` | `12/d` | `130..630c` |
| 99 | Vanilla | **Companion** *(Origin)* | `companion_2h_background.nut` | `+32.8` | **`0.20×`**: `HP 62..63, Res 42..43, Fat 99..101, Ini 102..103, MAtk 59..60, RAtk 36..38, MDef 3..4, RDef 3..4` | Keep `RAtk` *(clear `RDef`)* | `+32.8` | `1(22%) / 2(76%) / 3(2%)` | `89% / 11% / 0%` | **2.00★** | `43.5 ± 4.2` (`P95 51.1`) | `+0` | `12/d` | `140c` |
| 100 | Vanilla | **Companion** *(Origin)* | `companion_2h_southern_background.nut` | `+32.8` | **`0.20×`**: `HP 62..63, Res 42..43, Fat 99..101, Ini 102..103, MAtk 59..60, RAtk 36..38, MDef 3..4, RDef 3..4` | Keep `RAtk` *(clear `RDef`)* | `+32.8` | `1(22%) / 2(76%) / 3(2%)` | `89% / 11% / 0%` | **2.00★** | `43.5 ± 4.4` (`P95 51.6`) | `+0` | `12/d` | `140c` |
| 101 | Vanilla | **Executioner** | `executioner_background.nut` | `+33.9` | **`0.19×`**: `HP 63..64, Res 45..47, Fat 106..107, Ini 99..101, MAtk 54..64, RAtk 34..35, MDef 0, RDef -3..-2` | Keep `RAtk` | `+33.9` | `1(34%) / 2(65%) / 3(1%)` | `90% / 10% / 0%` | **1.84★** | `43.5 ± 6.8` (`P95 54.1`) | `+1..+6` | `12/d` | `640..7490c` |
| 102 | Vanilla | **Executioner** | `executioner_southern_background.nut` | `+33.9` | **`0.19×`**: `HP 63..64, Res 45..47, Fat 106..107, Ini 99..101, MAtk 54..64, RAtk 34..35, MDef 0, RDef -3..-2` | Keep `RAtk` | `+33.9` | `1(34%) / 2(65%) / 3(1%)` | `90% / 10% / 0%` | **1.84★** | `43.4 ± 7.0` (`P95 54.4`) | `+1..+6` | `12/d` | `640..7490c` |
| 103 | Reforged | **Old Swordmaster** | `rf_old_swordmaster_background.nut` | `+34.2` | **`0.19×`**: `HP 42..44, Res 45..47, Fat 82..83, Ini 94..96, MAtk 74..75, RAtk 31..33, MDef 15, RDef 2..3` | Keep `RAtk` *(clear `RDef`)* | `+34.2` | `1(42%) / 2(57%) / 3(1%)` | `90% / 10% / 0%` | **1.75★** | `43.8 ± 4.3` (`P95 52.0`) | `+1..+6` | `12/d` | `640..7490c` |
| 104 | Vanilla | **Swordmaster** | `swordmaster_background.nut` | `+34.2` | **`0.19×`**: `HP 42..44, Res 45..47, Fat 82..83, Ini 94..96, MAtk 74..75, RAtk 31..33, MDef 15, RDef 2..3` | Keep `RAtk` | `+34.2` | `1(42%) / 2(57%) / 3(1%)` | `90% / 10% / 0%` | **1.75★** | `43.7 ± 4.5` (`P95 51.7`) | `+1..+6` | `12/d` | `640..7490c` |
| 105 | Vanilla | **Squire** | `squire_background.nut` | `+36.0` | **`0.17×`**: `HP 54..56, Res 46..48, Fat 100..102, Ini 104..106, MAtk 54..62, RAtk 44..45, MDef 4..5, RDef 4..5` | — | `+36.0` | `0(1%) / 1(57%) / 2(42%)` | `91% / 9% / 0%` | **1.54★** | `44.8 ± 5.4` (`P95 54.1`) | `+1..+6` | `13/d` | `650..7500c` |
| 106 | XBE | **Berserker** | `berserker_background.nut` | `+36.8` | **`0.16×`**: `HP 66..68, Res 47..48, Fat 114..115, Ini 99..101, MAtk 54..58, RAtk 30..32, MDef 0..1, RDef -7..-6` | — | `+36.8` | `0(1%) / 1(71%) / 2(28%)` | `91% / 9% / 0%` | **1.38★** | `45.8 ± 5.7` (`P95 55.7`) | `+1..+6` | `13/d` | `660..7500c` |
| 107 | Vanilla | **Beast Slayer** | `beast_hunter_background.nut` | `+37.0` | **`0.16×`**: `HP 56..57, Res 46..47, Fat 100..102, Ini 110..112, MAtk 54..60, RAtk 45..47, MDef 2..3, RDef 2..3` | — | `+37.0` | `0(1%) / 1(71%) / 2(28%)` | `91% / 9% / 0%` | **1.38★** | `44.8 ± 4.6` (`P95 53.1`) | `+1..+6` | `13/d` | `660..7500c` |
| 108 | Vanilla | **Wildman** | `wildman_background.nut` | `+37.8` | **`0.16×`**: `HP 65..67, Res 45..47, Fat 115..116, Ini 99..101, MAtk 54..56, RAtk 34..35, MDef 0, RDef -3..-2` | — | `+37.8` | `0(3%) / 1(80%) / 2(17%)` | `92% / 8% / 0%` | **1.23★** | `44.2 ± 3.8` (`P95 51.1`) | `+1..+6` | `13/d` | `660..7510c` |
| 109 | XBE | **Bounty Hunter** | `bounty_hunter_background.nut` | `+37.8` | **`0.16×`**: `HP 54..56, Res 37..39, Fat 97..99, Ini 113..115, MAtk 62..63, RAtk 44..46, MDef 5..6, RDef 2..3` | — | `+37.8` | `0(3%) / 1(80%) / 2(17%)` | `92% / 8% / 0%` | **1.23★** | `44.4 ± 3.8` (`P95 51.6`) | `+1..+6` | `13/d` | `660..7510c` |
| 110 | Vanilla | **Assassin** | `assassin_southern_background.nut` | `+37.9` | **`0.16×`**: `HP 49..51, Res 44..46, Fat 89..91, Ini 122..123, MAtk 61..63, RAtk 36..38, MDef 9, RDef 2..3` | Clear `HP, Fat` | `+37.9` | `0(3%) / 1(80%) / 2(17%)` | `92% / 8% / 0%` | **1.23★** | `44.7 ± 3.9` (`P95 52.1`) | `+1..+6` | `13/d` | `660..7510c` |
| 111 | Vanilla | **Companion** *(Origin)* | `companion_1h_background.nut` | `+38.0` | **`0.16×`**: `HP 54..56, Res 42..43, Fat 99..101, Ini 104..106, MAtk 59..60, RAtk 41..43, MDef 7..8, RDef 7..8` | Keep `RAtk` | `+38.0` | `0(3%) / 1(80%) / 2(17%)` | `92% / 8% / 0%` | **1.23★** | `44.8 ± 3.8` (`P95 52.0`) | `+0` | `13/d` | `160c` |
| 112 | Vanilla | **Companion** *(Origin)* | `companion_1h_southern_background.nut` | `+38.0` | **`0.16×`**: `HP 54..56, Res 42..43, Fat 99..101, Ini 104..106, MAtk 59..60, RAtk 41..43, MDef 7..8, RDef 7..8` | Keep `RAtk` | `+38.0` | `0(3%) / 1(80%) / 2(17%)` | `92% / 8% / 0%` | **1.23★** | `44.9 ± 3.8` (`P95 52.4`) | `+0` | `13/d` | `160c` |
| 113 | XBE | **Bodyguard** | `bodyguard_background.nut` | `+39.1` | **`0.15×`**: `HP 62..64, Res 39..41, Fat 99..101, Ini 89..91, MAtk 53..55, RAtk 32..34, MDef 16..17, RDef 10` | Clear `Ini` | `+39.1` | `0(7%) / 1(86%) / 2(7%)` | `93% / 7% / 0%` | **1.07★** | `44.7 ± 3.7` (`P95 51.2`) | `+1..+6` | `13/d` | `670..7510c` |
| 114 | Vanilla | **Assassin** | `assassin_background.nut` | `+39.4` | **`0.14×`**: `HP 49..51, Res 44..46, Fat 89..91, Ini 122..123, MAtk 62..64, RAtk 36..38, MDef 9, RDef 2..3` | Clear `HP, Fat, RDef, Res` | `+39.4` | `0(10%) / 1(85%) / 2(5%)` | `94% / 6% / 0%` | **1.01★** | `44.9 ± 3.5` (`P95 50.7`) | `+1..+6` | `13/d` | `670..7520c` |
| 115 | Vanilla | **Barbarian** | `barbarian_background.nut` | `+39.4` | **`0.14×`**: `HP 62..63, Res 42..43, Fat 102..103, Ini 112..113, MAtk 59..60, RAtk 36..38, MDef 2..3, RDef 2..3` | — | `+39.4` | `0(10%) / 1(85%) / 2(5%)` | `94% / 6% / 0%` | **1.01★** | `44.9 ± 3.2` (`P95 50.2`) | `+1..+6` | `13/d` | `670..7520c` |
| 116 | XBE | **Lancer** | `lancer_background.nut` | `+39.5` | **`0.14×`**: `HP 54..56, Res 41..42, Fat 100..102, Ini 109..111, MAtk 63..64, RAtk 36..38, MDef 5..6, RDef 4..5` | Keep `RAtk` *(clear `RDef`)* | `+39.5` | `0(13%) / 1(83%) / 2(4%)` | `94% / 6% / 0%` | **0.96★** | `44.7 ± 3.5` (`P95 50.2`) | `+1..+6` | `13/d` | `670..7520c` |
| 117 | Vanilla | **Gladiator** | `gladiator_background.nut` | `+41.1` | **`0.13×`**: `HP 54..56, Res 39..41, Fat 94..96, Ini 104..106, MAtk 63..64, RAtk 43..45, MDef 9, RDef 9` | — | `+41.1` | `0(28%) / 1(71%) / 2(1%)` | `95% / 5% / 0%` | **0.77★** | `45.2 ± 3.5` (`P95 50.5`) | `+1..+6` | `14/d` | `680..7520c` |
| 118 | Vanilla | **Gladiator** | `gladiator_origin_background.nut` | `+41.1` | **`0.13×`**: `HP 54..56, Res 39..41, Fat 94..96, Ini 104..106, MAtk 63..64, RAtk 43..45, MDef 9, RDef 9` | — | `+41.1` | `0(28%) / 1(71%) / 2(1%)` | `95% / 5% / 0%` | **0.77★** | `45.4 ± 3.5` (`P95 50.8`) | `+1..+6` | `14/d` | `680..7520c` |
| 119 | Vanilla | **Gladiator** | `old_gladiator_background.nut` | `+41.1` | **`0.13×`**: `HP 54..56, Res 39..41, Fat 94..96, Ini 104..106, MAtk 63..64, RAtk 43..45, MDef 9, RDef 9` | — | `+41.1` | `0(28%) / 1(71%) / 2(1%)` | `95% / 5% / 0%` | **0.77★** | `45.3 ± 3.5` (`P95 50.7`) | `+1..+6` | `14/d` | `680..7520c` |
| 120 | Vanilla | **Adventurous Noble** | `adventurous_noble_background.nut` | `+42.5` | **`0.12×`** *(compressed)*: `HP 54..56, Res 51..53, Fat 97..98, Ini 104..106, MAtk 61..63, RAtk 36..38, MDef 9, RDef -5` | — | `+42.0` | `0(42%) / 1(57%) / 2(1%)` | `96% / 4% / 0%` | **0.61★** | `45.5 ± 3.6` (`P95 51.2`) | `+1..+6` | `14/d` | `680..7530c` |
| 121 | XBE | **Outlander** | `outlander_background.nut` | `+42.8` | **`0.13×`** *(compressed)*: `HP 57..59, Res 39..41, Fat 99..101, Ini 114..116, MAtk 61..62, RAtk 42..44, MDef 4, RDef 4` | — | `+41.7` | `0(42%) / 1(57%) / 2(1%)` | `96% / 4% / 0%` | **0.61★** | `45.0 ± 3.6` (`P95 50.8`) | `+1..+6` | `14/d` | `680..7530c` |
| 122 | Vanilla | **Converted Crusader** | `crucified_background.nut` | `+43.5` | **`0.12×`** *(compressed)*: `HP 54..56, Res 39..41, Fat 94..96, Ini 104..106, MAtk 62..64, RAtk 47..48, MDef 9, RDef 9` | — | `+42.4` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `45.2 ± 3.5` (`P95 51.0`) | `+1..+6` | `14/d` | `680..7530c` |
| 123 | Vanilla | **Sellsword** | `sellsword_background.nut` | `+43.5` | **`0.12×`** *(compressed)*: `HP 54..56, Res 39..41, Fat 94..96, Ini 104..106, MAtk 62..64, RAtk 47..48, MDef 9, RDef 9` | — | `+42.4` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `45.3 ± 3.5` (`P95 51.1`) | `+1..+6` | `14/d` | `680..7530c` |
| 124 | Vanilla | **Crusader** | `crusader_background.nut` | `+49.1` | **`0.11×`** *(compressed)*: `HP 63..65, Res 49..51, Fat 103..105, Ini 104..106, MAtk 60..62, RAtk 29..30, MDef 2..3, RDef 0` | Keep `RAtk` *(clear `RDef`)* | `+43.1` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `46.2 ± 3.8` (`P95 52.5`) | `+8` | `14/d` | `11500c` |
| 125 | Vanilla | **Orc Slayer** | `orc_slayer_background.nut` | `+49.1` | **`0.11×`** *(compressed)*: `HP 63..65, Res 49..51, Fat 103..105, Ini 104..106, MAtk 60..62, RAtk 29..30, MDef 2..3, RDef 0` | Keep `RAtk` *(clear `RDef`)* | `+43.1` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `46.1 ± 3.7` (`P95 52.4`) | `+8` | `14/d` | `11500c` |
| 126 | Vanilla | **Oathtaker** | `old_paladin_background.nut` | `+50.8` | **`0.12×`** *(compressed)*: `HP 61..63, Res 47..48, Fat 92..94, Ini 115..116, MAtk 61..63, RAtk 34..35, MDef 6, RDef -5` | Keep `RAtk` *(clear `HP`)* | `+42.5` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `45.3 ± 3.5` (`P95 51.3`) | `+1..+6` | `14/d` | `680..7530c` |
| 127 | Vanilla | **Oathtaker** | `paladin_background.nut` | `+50.8` | **`0.12×`** *(compressed)*: `HP 61..63, Res 47..48, Fat 92..94, Ini 115..116, MAtk 61..63, RAtk 34..35, MDef 6, RDef -5` | Keep `RAtk` *(clear `HP`)* | `+42.5` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `45.4 ± 3.6` (`P95 51.5`) | `+1..+6` | `14/d` | `680..7530c` |
| 128 | Vanilla | **Lindwurm Slayer** | `lindwurm_slayer_background.nut` | `+51.2` | **`0.12×`** *(compressed)*: `HP 58..60, Res 43..45, Fat 98..100, Ini 113..114, MAtk 58..60, RAtk 44..45, MDef 6, RDef -1..0` | — | `+42.7` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `45.5 ± 3.6` (`P95 51.5`) | `+1..+6` | `14/d` | `690..7530c` |
| 129 | Vanilla | **Hedge Knight** | `hedge_knight_background.nut` | `+52.4` | **`0.12×`** *(compressed)*: `HP 65..66, Res 40..41, Fat 105..106, Ini 94..95, MAtk 60..61, RAtk 36..38, MDef 7, RDef 2..3` | Keep `RAtk` *(clear `Ini`)* | `+42.9` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `45.9 ± 3.3` (`P95 51.3`) | `+1..+6` | `14/d` | `690..7530c` |
| 130 | XBE | **Folk Hero** | `folk_hero_background.nut` | `+63.5` | **`0.10×`** *(compressed)*: `HP 65..66, Res 39, Fat 106..107, Ini 105, MAtk 62..63, RAtk 37, MDef 5, RDef 3..4` | Keep `RAtk` *(clear `Ini, RDef`)* | `+46.2` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `49.1 ± 3.3` (`P95 54.4`) | `+1..+6` | `14/d` | `710..7550c` |
| 131 | XBE | **Champion** | `champion_background.nut` | `+67.8` | **`0.10×`** *(compressed)*: `HP 65..66, Res 42..43, Fat 102..103, Ini 90..91, MAtk 62..63, RAtk 37, MDef 7..8, RDef 5..6` | Keep `RAtk` *(clear `Ini, RDef`)* | `+46.6` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `49.4 ± 3.3` (`P95 54.9`) | `+1..+6` | `14/d` | `710..7560c` |
| 132 | Reforged | **Renowned Swordmaster** | `rf_renowned_swordmaster_background.nut` | `+80.5` | **`0.10×`** *(compressed)*: `HP 55, Res 41..42, Fat 99..100, Ini 114..115, MAtk 65..66, RAtk 31..32, MDef 10, RDef 2..3` | Keep `RAtk` *(clear `RDef`)* | `+47.7` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `50.6 ± 3.4` (`P95 56.2`) | `+1..+6` | `15/d` | `710..7560c` |
| 133 | XBE | **Paladin** | `paladin_commander_background.nut` | `+83.2` | **`0.10×`** *(compressed)*: `HP 64..65, Res 46..47, Fat 104..105, Ini 101, MAtk 60..61, RAtk 37, MDef 7..8, RDef 0..1` | Keep `RAtk` *(clear `Ini, RDef`)* | `+48.9` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `51.7 ± 3.4` (`P95 57.3`) | `+1..+6` | `15/d` | `720..7570c` |

---

### 6.2 Hardened Mod Attribute Override Variants (Automatic Runtime Adaptation)

| Background | Hardened Attribute Override | Hardened `S_0` | `VarMult` | Excluded Talents | Talented Attrs `N` | Star Tiers (`1★ / 2★ / 3★`) | `E[★]` | Lvl-11 `Mean ± SD` (`P95`) | Pending Lvls | Base Wage | No-Gear Cost |
| :--- | :--- | :---: | :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Bowyer** (`bowyer_background.nut`) | `HP [-5..0] (was 0), RAtk +15 (was +10)` | `+7.5` | `0.40×` | Keep `MAtk` | `5(54%) / 6(46%)` | `32% / 66% / 2%` | **9.28★** | `39.6 ± 5.2` (`P95 48.1`) | `+0` | `8/d` | `70c` |
| **Pimp** (`pimp_background.nut`) | `MAtk [0..+5] (was -5)` | `+21.5` | `0.29×` | — | `2(1%) / 3(78%) / 4(21%)` | `77% / 23% / 0%` | **3.94★** | `41.4 ± 5.4` (`P95 51.1`) | `+0` | `10/d` | `100c` |
| **Thief** (`thief_background.nut`) | `RDef +5 (was [+5..+8])` | `+27.8` | `0.24×` | — | `2(58%) / 3(42%)` | `85% / 15% / 0%` | **2.78★** | `42.8 ± 5.5` (`P95 53.1`) | `+0` | `11/d` | `120c` |
| **Southern Assassin** (`assassin_southern_background.nut`) | `RAtk [+5..+10] (was 0)` | `+55.6` | `0.11×` | Clear `HP, Fat` | `0(50%) / 1(50%)` | `96% / 4% / 0%` | **0.52★** | `46.6 ± 3.4` (`P95 52.3`) | `+1..+6` | `14/d` | `690..7540c` |

---

### 6.3 Mid-Campaign Event-Conversion Backgrounds (5 Backgrounds)

| # | Background | Script | Event Mechanism & Handling |
| :-: | :--- | :--- | :--- |
| 134 | **Converted Cultist** | `converted_cultist_background.nut` | Swaps onto an existing recruit during cultist conversion events (`+2 Bravery`). Preserves existing stars & stats; daily wage reflects current `BaseProperties`. |
| 135 | **King's Guard** | `kings_guard_background.nut` | `kings_guard_1_event` spawns a special Cripple (`_addTraits = false`, scripted `2★ MAtk, 3★ MDef, 3★ RDef`), then `kings_guard_2_event` adds `+61` flat stats. Preserves scripted event reward; daily wage scales up automatically. |
| 136 | **Monk turned Flagellant** | `monk_turned_flagellant_background.nut` | Swaps onto an existing Monk in `flagellant_vs_monk_event`. Preserves existing stars & stats. |
| 137 | **Pacified Flagellant** | `pacified_flagellant_background.nut` | Swaps onto an existing Flagellant in `flagellant_vs_monk_event`. Preserves existing stars & stats. |
| 138 | **Regent in Absentia** | `regent_in_absentia_background.nut` | Swaps onto an existing Disowned Noble in `disowned_noble_welcomed_back_event` (`+10..15 Res, +6..10 Ini, +2..4 MDef, +3..5 RDef`). Preserves existing stars; daily wage scales up automatically. |
