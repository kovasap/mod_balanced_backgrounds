# Balanced Backgrounds — Architecture & Balance Plan

This document specifies the complete mathematical model, UI/backend architecture, cross-mod compatibility strategy, and per-background stat/star/cost plan for **Balanced Backgrounds** (see [README.md](README.md)).

---

## 1. Design Goals & Finalized Decisions

1. **Linear Variance Curve ("Sure-Thing" Highborn vs. High-Ceiling Lowborn)**:
   - **Linear Variance Reduction**: Both **starting attribute roll ranges** (`VarMult`) and **talent star count variance** (`σ_N`) decrease linearly from Vanilla Lowborn (`Beggar`/`Cripple` at `S_adj ≈ -8 SSP` $\to$ `2.30×` roll width, wide `0..7` star count spread) down to Vanilla Premium (`Hedge Knight`/`Adventurous Noble`/`Sellsword` at `S_adj ≈ +45 SSP` $\to$ `0.20×` roll width, tight `0..2` star count spread), passing right through Vanilla `~1.0×` at **Militia** (`S_adj = +23.3 SSP`). Modded Reforged/XBE backgrounds map onto the exact same linear curve and clamp cleanly to `[0.20×, 2.30×]`.
   - **30% Upset Rate & Higher Lowborn Ceiling**:
     - **Premium Backgrounds** (`Hedge Knight`, `Gladiator`, `Adventurous Noble`, `Sellsword`, `Swordmaster`) have a higher **average** Level-11 budget (`~50–51.5 SSP`) with very tight standard deviation (`±6.5–7.5 SSP`), making them a dependable **"sure thing"** (`P95 ≈ 61–65 SSP`).
     - **Lowborn Backgrounds** (`Beggar`, `Refugee`, `Apprentice`, `Daytaler`, `Vagabond`) have a lower **average** Level-11 budget (`~38–41 SSP`) with wide standard deviation (`±20–23 SSP`), giving a random Lowborn recruit **~30% probability (`30.1%`) to outscale a random Premium recruit at Level 11** while reaching a **substantially higher top-end ceiling** when you find "the right one" (**`P95 ≈ 70–75 SSP`, `P99 ≈ 84–87 SSP`** vs. Premium `P95 ≈ 62–65 SSP`, `P99 ≈ 70–72 SSP`).
     - **Militia** (`S_adj = +23.3 SSP`) anchors the middle of both curves (`Mean ≈ 46.2 SSP`, `SD ≈ 12.6 SSP`, `VarMult = 1.06×`).
   - **Soft Midpoint Outlier Compression**: 107 of 133 backgrounds keep their exact Vanilla / Reforged / Hardened / XBE attribute midpoints untouched; only the 26 extreme low/high outliers (`S_0 < -8.0` or `S_0 > +42.0 SSP`) have their midpoints soft-compressed into `[-10.5, +46.5] SSP`.
   - **Thematic `ExcludedTalents` Filtering**: Clear survival/ceiling lockouts (`HP`, `Fat`, `Resolve` on lowborns) and multi-stat dump funneling (`Ini`, `RDef`, `MDef`, `HP` on elites), preserving **at most 1 thematic exclusion** (`RangedSkill` on pure melee/chivalric backgrounds, `MeleeSkill` on pure ranged/bowcraft backgrounds, `Bravery` on `Deserter`, `Initiative` on `Cripple`, and `Hitpoints` on XBE `Leper`).
   - **Origin Starting Roster Support**: Clear `IsUntalented` on `Companion` backgrounds, skip hardcoded `Companion` star assignments, and hook `starting_scenario.onSpawnAssets()` so Day-1 Origin characters use Balanced Backgrounds star probabilities before Reforged rebuilds dynamic perk trees in `onSpawnPlayer()`.
2. **Daily Wage & Hiring Cost Based on Base Stats Alone**:
   - Both `DailyWage` and equipment-free `BaseHiringCost` (plus `TryoutCost`) are pure functions of a character's actual `BaseProperties` attributes—never background `DailyCost` or `HiringCost` presets, and **star potential is unpriced at Level 1**.
   - Daily wages scale naturally from Level 1 (`~5–14` crowns/day depending on rolled base stats) to Level 11 (`~28–32` crowns/day depending on realized Level-11 stats) without separate `1.1^(level - 1)` background wage compounding.
3. **Optional Equipment-Free Hiring**:
   - Players can toggle **"Include Equipment"** in the Town Hire Screen to hire any recruit without their starting gear, paying only `BaseHiringCost * HiringCostMult`.
4. **Zero-Serialization Save Compatibility & Dynamic Mod Support**:
   - All calculations evaluate `onChangeAttributes()` and `BaseProperties` dynamically at runtime in a late load-order bucket (`>msu, >mod_reforged, >mod_hardened, >mod_backgrounds_and_events`), requiring **zero custom save-file serialization** and automatically supporting [battle-brothers-xbe](https://github.com/Suor/battle-brothers-xbe), [Reforged](https://github.com/Battle-Modders/mod-reforged), and [Hardened](https://github.com/Darxo/Hardened).

---

## 2. Pillar 1: Linear Variance & Talent Star Calibration

```mermaid
flowchart LR
    A["Read onChangeAttributes()"] --> B["Soft-Compress Extreme Midpoints (S < -8 or S > 42)"]
    B --> C["Apply Linear Stat Roll Variance VarMult(S_adj) in [0.20x, 2.30x]"]
    C --> D["Filter ExcludedTalents (Keep <=1 Thematic Flaw)"]
    D --> E["Solve u in [0, 1] for Linear Mean & Gaussian Star-Count Spread"]
    E --> F["Roll Count N (max open-1) & 1★/2★/3★ Tiers"]
```

### 2.1 Standard Stat Points (SSP) Evaluation
Base human Level-1 averages (`character_background.buildAttributes()`, before `onChangeAttributes()`):
- `Hitpoints`: `55.0` (`50..60`, `baseHalf = 5.0`)
- `Bravery` (Resolve): `35.0` (`30..40`, `baseHalf = 5.0`)
- `Stamina` (Fatigue): `95.0` (`90..100`, `baseHalf = 5.0`)
- `Initiative`: `105.0` (`100..110`, `baseHalf = 5.0`)
- `MeleeSkill`: `52.0` (`47..57`, `baseHalf = 5.0`)
- `RangedSkill`: `37.0` (`32..42`, `baseHalf = 5.0`)
- `MeleeDefense`: `2.5` (`0..5`, `baseHalf = 2.5`)
- `RangedDefense`: `2.5` (`0..5`, `baseHalf = 2.5`)

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
1. **Midpoint Outlier Compression**:
   - **In-Bounds Core (`-8.0 ≤ S_0 ≤ +42.0 SSP`, 107 of 133 backgrounds)**: Midpoints 100% unchanged.
   - **High-Stat Outliers (`S_0 > +42.0 SSP`)**: Positive deltas scaled so $S_{\text{mid}} = \min(46.5,\; 42.0 + 0.12 \cdot (S_0 - 42.0))$.
   - **Low-Stat Outliers (`S_0 < -8.0 SSP`)**: Negative deltas scaled so $S_{\text{mid}} = \max(-10.5,\; -8.0 + 0.10 \cdot (S_0 + 8.0))$.
2. **Linear Starting Attribute Roll Width (`VarMult`)**:
   Anchored linearly between Vanilla Lowborn (`S = -8.0 SSP` $\to$ `2.30×`) and Vanilla Premium (`S = +45.0 SSP` $\to$ `0.20×`), clamped to `[0.20, 2.30]` for modded outliers:
   $$\text{VarMult}(S_{\text{mid}}) = 2.30 - 2.10 \cdot \text{clamp}\!\left(\frac{S_{\text{mid}} - (-8.0)}{45.0 - (-8.0)},\; 0,\; 1\right)$$
   For each attribute $k$ with base half-width $h_k \in \{5.0, 2.5\}$ and midpoint delta $m_k$, target half-width is $h'_k = \text{VarMult} \cdot h_k$, encoded directly in `onChangeAttributes()` as `[round(m_k - h'_k + h_k), round(m_k + h'_k - h_k)]` (with safety floors `[30 HP, 12 Res, 65 Fat, 60 Ini, 25 MAtk, 15 RAtk]` and preserving `MeleeSkill[0] < 8` for Reforged's `Old Swordmaster` origin check).
   - **Lowborn (`Daytaler`, `VarMult = 1.92×`)**: Rolls `MAtk 42..62`, `HP 45..65`, `MDef -2..+7` (wide prodigy/dud spread).
   - **Militia (`VarMult = 1.06×`)**: Rolls `MAtk 52..62`, `HP 50..60`, `MDef 2..7` (classic Vanilla feel).
   - **Premium (`Hedge Knight`, `VarMult = 0.29×`)**: Rolls `MAtk 59..61`, `HP 63..66`, `MDef 6..8` (rock-solid "sure thing").
   - **Reforged Base-Attribute Tooltip Sync**: Because Reforged's `getBaseAttributesTooltip()` reads `BaseAttributes + onChangeAttributes()`, hiring tooltips automatically show each background's exact wide or tight roll ranges!

### 2.3 Thematic `ExcludedTalents` Filter & Hardened Safety Cap
- Preserve `Bravery` on `background.deserter`, `Initiative` on `background.cripple`, `Hitpoints` on `background.hackflows_leper`, and at most **1** offensive exclusion (`RangedSkill` or `MeleeSkill`) elsewhere, clearing all other survival/funneling exclusions.
- Cap talented attribute count $N \le \text{open\_attrs} - 1$ (`≤ 7` when 8 open, `≤ 6` when 7 open) so Hardened's `Discovered Talent` perk always finds at least one `0★` attribute.

### 2.4 Linear Star-Count Variance & 30% Upset Calibration (`u` in `[0.0, 1.0]`)
- **Linear Mean Level-11 Target**:
  $$E_{11,\text{target}}(S_{\text{adj}}) = 45.00 + 0.33 \cdot \big(S_{\text{adj}} - 23.30\big)$$
  - **Lowborn (`S_adj ≈ -8..+2`)**: `E_11 ≈ 37–40.5 SSP` mean, `SD ≈ 21–23 SSP`, **`P95 ≈ 71–75 SSP`**, **`P99 ≈ 84–87 SSP`**.
  - **Militia (`S_adj = +23.3`)**: `E_11 ≈ 46.2 SSP` mean, `SD ≈ 12.6 SSP`.
  - **Premium (`S_adj ≈ +35..+43`)**: `E_11 ≈ 49–51.5 SSP` mean, `SD ≈ 6.3–9.5 SSP`, **`P95 ≈ 60–65 SSP`**, **`P99 ≈ 70–73 SSP`**.
  - **Result**: Across Vanilla Lowborn vs. Vanilla Premium recruits, **`P(Lowborn > Premium at Level 11) ≈ 30%`** (`30.1%`), while top-decile Lowborns (`P90–P99`) substantially outscale top-decile Premium recruits!
- **Discrete Gaussian Star-Count Variance (`σ_N(u) = 0.30 + 2.50 · u`)**:
  - For $u \in [0.00, 0.40]$: $\mu_N = 0.15 + \frac{u}{0.40}(3.00 - 0.15)$; $(p_1, p_2, p_3)$ interpolates from `(92%, 8%, 0%)` to `(60%, 30%, 10%)`.
  - For $u \in [0.40, 1.00]$: $\mu_N = 3.00 + \frac{u - 0.40}{0.60}(6.20 - 3.00)$; $(p_1, p_2, p_3)$ interpolates from `(60%, 30%, 10%)` to `(10%, 15%, 75%)`.
  - Count weights on $c \in \{0, \dots, \text{max\_n}\}$ follow $w(c) \propto \exp\!\big(-\frac{1}{2}((c - \mu_N)/\sigma_N)^2\big)$, growing linearly from ultra-tight `σ_N = 0.30` on Premium (`0–1` or `1–2` stars) to wide `σ_N = 2.80` on Lowborn (`0..7` talented attributes!).

---

## 3. Pillar 2: Base-Stat-Only Daily Wage & Hiring Cost

### 3.1 Individual Base-Stat Score ($B_{\text{actor}}$)
Computed from `actor.getBaseProperties()` (subtracting Hardened's global `HD_HitpointModifier = +5` when active) relative to Base Human `[55, 35, 95, 105, 52, 37, 2.5, 2.5]` using the SSP weights in Section 2.1.

### 3.2 Daily Wage Formula (`character_background.onUpdate`)
$$\text{StatDailyWage}(B_{\text{actor}}) = \max\!\Big(3,\; \text{round}\big(6.8 + 0.165 \cdot B_{\text{actor}}\big)\Big)$$
- Scales naturally with `BaseProperties` from Level 1 (`~5–14/day`) to Level 11 (`~28–32/day`, where a rare `P99` Lowborn prodigy who grows to huge stats eventually commands a veteran's wage to match!).
- Preserves `trait.player` (`0` wage), `scenario.manhunters` unpaid `Indebted` (`0` wage), flat event wage changes on `BaseProperties.DailyWage`, and `DailyWageMult` traits.

### 3.3 Base Hiring Cost, Equipped Cost & Tryout Cost
$$B_{\text{hire}} = B_{\text{actor}} + 12.0 \cdot (L - 1)$$
$$\text{BaseHiringCost} = 10 \cdot \max\!\Big(2,\; \text{ceil}\big(5.0 \cdot e^{0.030 \cdot B_{\text{hire}}}\big)\Big)$$
- Equipped `HiringCost` adds `1.25×` equipment value rounded up to 10 crowns; `TryoutCost` scales off `BaseHiringCost` rather than gear value.

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

- **Backend**: `player.getBaseHiringCost()`, `data_helper.convertEntityHireInformationToUIData()`, `town_hire_dialog_module.onHireRosterEntryWithoutEquipment()`, and `tooltip_events.general_queryUIElementTooltipData()`.
- **Frontend**: `"Include Equipment"` checkbox in `WorldTownScreenHireDialogModule` footer dynamically switching roster list cards, `InitialMoneyCostsText`, and `HireButton` state between `FullMoneyCost` and `NoEquipMoneyCost`.

---

## 5. Repository File Structure

```text
mod_balanced_backgrounds/
├── README.md
├── AGENTS.md
├── PLAN.md
├── scripts/
│   └── !mods_preload/
│       └── mod_balanced_backgrounds.nut
├── mod_balanced_backgrounds/
│   ├── config/
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

Columns:
- **Orig `S_0`**: Original midpoint Starting Budget in SSP.
- **`VarMult` & Level-1 Roll Ranges**: Linear variance multiplier (`2.30×` lowborn $\to$ `0.20×` premium) and resulting Level-1 attribute roll ranges (`Base + onChangeAttributes()`).
- **Excluded Talents**: Thematic single-stat exclusions preserved vs. cleared.
- **Adj `S_adj`**: Expected starting SSP after outlier compression.
- **Talented Attrs `N`** / **Star Tiers (`1★ / 2★ / 3★`)** / **`E[★]`**: Discrete Gaussian attribute-count spread, star-tier weights, and expected total stars.
- **Lvl-11 `Mean ± SD` (`P95`)**: Simulated Level-11 SSP mean, standard deviation (showing linear variance narrowing), and 95th-percentile prodigy ceiling (`P95`).
- **Lvl-1 Wage** / **No-Gear Cost**: Expected Level-1 daily wage and equipment-free signing cost at midpoint stats.

| # | Src | Background | Script | Orig `S_0` | `VarMult` & Level-1 Roll Ranges | Excluded Talents | Adj `S_adj` | Talented Attrs `N` | Star Tiers (`1★/2★/3★`) | `E[★]` | Lvl-11 `Mean ± SD` (`P95`) | Wage | No-Gear |
| :-: | :--- | :--- | :--- | :---: | :--- | :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: |
| 1 | Vanilla | **Cripple** | `cripple_background.nut` | `-35.2` | **`2.30×`** *(mid ×0.28)*: `HP 39..62, Res 23..47, Fat 82..105, Ini 88..112, MAtk 39..63, RAtk 25..48, MDef -3..8, RDef -3..8` | Keep `Ini` *(clear `HP`)* | `-9.5` | `0..6 (peak 6@25%)` | `18% / 18% / 64%` | **10.28★** | `36.0 ± 23.5` (`P95 72.3`) | `5/d` | `40c` |
| 2 | Vanilla | **Cripple** | `cripple_southern_background.nut` | `-35.2` | **`2.30×`** *(mid ×0.28)*: `HP 39..62, Res 23..47, Fat 82..105, Ini 88..112, MAtk 39..63, RAtk 25..48, MDef -3..8, RDef -3..8` | Keep `Ini` *(clear `HP`)* | `-9.5` | `0..6 (peak 6@25%)` | `18% / 18% / 64%` | **10.28★** | `36.0 ± 23.5` (`P95 71.8`) | `5/d` | `40c` |
| 3 | Vanilla | **Beggar** | `beggar_background.nut` | `-27.5` | **`2.30×`** *(mid ×0.35)*: `HP 39..63, Res 20..44, Fat 79..103, Ini 93..117, MAtk 40..64, RAtk 25..49, MDef -3..8, RDef -3..8` | Clear `HP, Res` | `-11.0` | `0..7 (peak 5@20%)` | `16% / 17% / 67%` | **11.82★** | `36.2 ± 23.1` (`P95 72.3`) | `5/d` | `40c` |
| 4 | Vanilla | **Beggar** | `beggar_southern_background.nut` | `-27.5` | **`2.30×`** *(mid ×0.35)*: `HP 39..63, Res 20..44, Fat 79..103, Ini 93..117, MAtk 40..64, RAtk 25..49, MDef -3..8, RDef -3..8` | Clear `HP, Res` | `-11.0` | `0..7 (peak 5@20%)` | `16% / 17% / 67%` | **11.82★** | `37.2 ± 22.9` (`P95 73.3`) | `5/d` | `40c` |
| 5 | Vanilla | **Historian** | `historian_background.nut` | `-18.5` | **`2.28×`** *(mid ×0.3)*: `HP 42..65, Res 24..46, Fat 82..104, Ini 94..116, MAtk 39..61, RAtk 25..47, MDef -3..8, RDef -3..8` | Clear `HP, Fat` | `-7.5` | `0..7 (peak 6@20%)` | `23% / 19% / 58%` | **10.83★** | `37.0 ± 22.4` (`P95 71.7`) | `6/d` | `40c` |
| 6 | Vanilla | **Historian** | `historian_southern_background.nut` | `-18.5` | **`2.28×`** *(mid ×0.3)*: `HP 42..65, Res 24..46, Fat 82..104, Ini 94..116, MAtk 39..61, RAtk 25..47, MDef -3..8, RDef -3..8` | Clear `HP, Fat` | `-7.5` | `0..7 (peak 6@20%)` | `23% / 19% / 58%` | **10.83★** | `37.3 ± 23.2` (`P95 73.0`) | `6/d` | `40c` |
| 7 | Vanilla | **Indebted** | `slave_background.nut` | `-14.0` | **`2.30×`** *(mid ×0.55)*: `HP 37..61, Res 22..45, Fat 83..107, Ini 90..114, MAtk 40..64, RAtk 25..49, MDef -3..8, RDef -3..8` | Clear `HP, Res` | `-8.4` | `0..7 (peak 5@20%)` | `21% / 18% / 61%` | **11.11★** | `36.4 ± 23.3` (`P95 72.0`) | `5/d` | `40c` |
| 8 | Vanilla | **Indebted** | `slave_southern_background.nut` | `-14.0` | **`2.30×`** *(mid ×0.7)*: `HP 36..59, Res 18..41, Fat 88..112, Ini 89..113, MAtk 40..64, RAtk 25..49, MDef -3..8, RDef -3..8` | Clear `HP, Res` | `-9.2` | `0..7 (peak 5@21%)` | `20% / 18% / 62%` | **11.28★** | `36.5 ± 23.4` (`P95 72.9`) | `5/d` | `40c` |
| 9 | XBE | **Cartographer** | `cartographer_background.nut` | `-12.5` | **`2.30×`** *(mid ×0.7)*: `HP 38..61, Res 22..46, Fat 81..105, Ini 93..117, MAtk 40..64, RAtk 25..49, MDef -3..8, RDef -3..8` | — | `-8.5` | `0..7 (peak 5@20%)` | `21% / 18% / 61%` | **11.11★** | `37.8 ± 23.3` (`P95 74.0`) | `5/d` | `40c` |
| 10 | Vanilla | **Servant** | `servant_background.nut` | `-12.4` | **`2.30×`** *(mid ×0.7)*: `HP 39..63, Res 19..43, Fat 79..103, Ini 96..119, MAtk 40..64, RAtk 25..49, MDef -3..8, RDef -2..9` | — | `-9.4` | `0..7 (peak 5@21%)` | `20% / 18% / 62%` | **11.28★** | `35.7 ± 23.2` (`P95 71.5`) | `5/d` | `40c` |
| 11 | Vanilla | **Servant** | `servant_southern_background.nut` | `-12.4` | **`2.30×`** *(mid ×0.7)*: `HP 39..63, Res 19..43, Fat 79..103, Ini 96..119, MAtk 40..64, RAtk 25..49, MDef -3..8, RDef -2..9` | — | `-9.4` | `0..7 (peak 5@21%)` | `20% / 18% / 62%` | **11.28★** | `35.5 ± 24.0` (`P95 73.6`) | `5/d` | `40c` |
| 12 | XBE | **Leper** | `leper_background.nut` | `-12.4` | **`2.30×`** *(mid ×0.85)*: `HP 54..77, Res 26..49, Fat 76..99, Ini 86..109, MAtk 38..61, RAtk 15..38, MDef -2..9, RDef -3..8` | Keep `HP` | `-9.5` | `0..6 (peak 6@26%)` | `15% / 17% / 68%` | **10.65★** | `36.0 ± 23.6` (`P95 74.1`) | `5/d` | `40c` |
| 13 | Vanilla | **Indebted** | `slave_barbarian_background.nut` | `-6.7` | **`2.25×`**: `HP 44..66, Res 16..39, Fat 89..111, Ini 89..111, MAtk 41..63, RAtk 26..48, MDef -5..7, RDef -5..7` | Clear `HP, Res` | `-6.7` | `0..7 (peak 6@20%)` | `24% / 19% / 57%` | **10.67★** | `36.1 ± 22.4` (`P95 71.0`) | `6/d` | `50c` |
| 14 | Vanilla | **Eunuch** | `eunuch_background.nut` | `-6.5` | **`2.24×`**: `HP 44..66, Res 19..41, Fat 84..106, Ini 89..111, MAtk 41..63, RAtk 26..48, MDef -3..8, RDef -3..8` | — | `-6.5` | `0..7 (peak 6@20%)` | `24% / 19% / 57%` | **10.67★** | `37.5 ± 22.1` (`P95 71.3`) | `6/d` | `50c` |
| 15 | Vanilla | **Eunuch** | `eunuch_southern_background.nut` | `-6.5` | **`2.24×`**: `HP 44..66, Res 19..41, Fat 84..106, Ini 89..111, MAtk 41..63, RAtk 26..48, MDef -3..8, RDef -3..8` | — | `-6.5` | `0..7 (peak 6@20%)` | `24% / 19% / 57%` | **10.67★** | `36.8 ± 22.6` (`P95 71.9`) | `6/d` | `50c` |
| 16 | Vanilla | **Refugee** | `refugee_background.nut` | `-5.1` | **`2.19×`**: `HP 38..59, Res 19..41, Fat 90..112, Ini 94..116, MAtk 41..63, RAtk 26..48, MDef -3..8, RDef -2..8` | — | `-5.1` | `0..7 (peak 5@21%)` | `27% / 20% / 53%` | **10.28★** | `38.8 ± 22.5` (`P95 74.4`) | `6/d` | `50c` |
| 17 | XBE | **Painter** | `painter_background.nut` | `-5.1` | **`2.19×`**: `HP 38..60, Res 24..46, Fat 83..105, Ini 97..118, MAtk 41..63, RAtk 26..48, MDef -3..8, RDef -3..8` | — | `-5.1` | `0..7 (peak 5@21%)` | `27% / 20% / 53%` | **10.28★** | `37.1 ± 22.7` (`P95 72.5`) | `6/d` | `50c` |
| 18 | XBE | **Herbalist** | `herbalist_background.nut` | `-5.0` | **`2.18×`**: `HP 44..66, Res 23..45, Fat 83..105, Ini 94..116, MAtk 39..61, RAtk 26..48, MDef -3..8, RDef -3..8` | — | `-5.0` | `0..7 (peak 5@21%)` | `27% / 20% / 53%` | **10.28★** | `37.7 ± 21.8` (`P95 71.9`) | `6/d` | `50c` |
| 19 | Vanilla | **Minstrel** | `minstrel_background.nut` | `-4.6` | **`2.17×`**: `HP 40..62, Res 32..53, Fat 74..96, Ini 97..118, MAtk 41..63, RAtk 26..48, MDef -3..8, RDef -3..8` | — | `-4.6` | `0..7 (peak 5@21%)` | `28% / 20% / 52%` | **10.10★** | `37.3 ± 22.4` (`P95 72.2`) | `6/d` | `50c` |
| 20 | Vanilla | **Tailor** | `tailor_background.nut` | `-4.6` | **`2.17×`**: `HP 43..64, Res 24..46, Fat 79..101, Ini 97..118, MAtk 41..63, RAtk 26..48, MDef -3..8, RDef -3..8` | — | `-4.6` | `0..7 (peak 5@21%)` | `28% / 20% / 52%` | **10.10★** | `36.9 ± 22.4` (`P95 71.5`) | `6/d` | `50c` |
| 21 | Vanilla | **Tailor** | `tailor_southern_background.nut` | `-4.6` | **`2.17×`**: `HP 43..64, Res 24..46, Fat 79..101, Ini 97..118, MAtk 41..63, RAtk 26..48, MDef -3..8, RDef -3..8` | — | `-4.6` | `0..7 (peak 5@21%)` | `28% / 20% / 52%` | **10.10★** | `37.0 ± 22.1` (`P95 72.1`) | `6/d` | `50c` |
| 22 | Vanilla | **Monk** | `monk_background.nut` | `-1.5` | **`2.04×`**: `HP 45..65, Res 36..56, Fat 80..100, Ini 95..115, MAtk 37..57, RAtk 27..47, MDef -3..8, RDef -3..8` | — | `-1.5` | `0..7 (peak 5@21%)` | `32% / 22% / 46%` | **9.42★** | `39.6 ± 21.2` (`P95 73.8`) | `7/d` | `50c` |
| 23 | Vanilla | **Peddler** | `peddler_background.nut` | `-1.5` | **`2.04×`**: `HP 45..65, Res 25..45, Fat 85..105, Ini 98..119, MAtk 32..53, RAtk 27..47, MDef 2..12, RDef 2..12` | — | `-1.5` | `0..7 (peak 5@21%)` | `32% / 22% / 46%` | **9.42★** | `38.5 ± 21.7` (`P95 73.1`) | `7/d` | `50c` |
| 24 | Vanilla | **Peddler** | `peddler_southern_background.nut` | `-1.5` | **`2.04×`**: `HP 45..65, Res 25..45, Fat 85..105, Ini 98..119, MAtk 32..53, RAtk 27..47, MDef 2..12, RDef 2..12` | — | `-1.5` | `0..7 (peak 5@21%)` | `32% / 22% / 46%` | **9.42★** | `37.3 ± 21.4` (`P95 71.9`) | `7/d` | `50c` |
| 25 | Vanilla | **Apprentice** | `apprentice_background.nut` | `+0.0` | **`1.98×`**: `HP 45..65, Res 25..45, Fat 85..105, Ini 95..115, MAtk 42..62, RAtk 27..47, MDef -2..7, RDef -2..7` | — | `+0.0` | `0..7 (peak 5@22%)` | `34% / 22% / 44%` | **9.16★** | `39.4 ± 20.4` (`P95 70.9`) | `7/d` | `50c` |
| 26 | XBE | **Cook** | `cook_background.nut` | `+1.3` | **`1.93×`**: `HP 56..76, Res 20..40, Fat 84..103, Ini 91..111, MAtk 42..62, RAtk 25..45, MDef -2..7, RDef -2..7` | Clear `Fat` | `+1.3` | `0..7 (peak 4@20%)` | `35% / 23% / 42%` | **8.90★** | `39.8 ± 20.8` (`P95 72.8`) | `7/d` | `60c` |
| 27 | Vanilla | **Killer on the Run** | `killer_on_the_run_background.nut` | `+1.4` | **`1.93×`**: `HP 45..65, Res 20..40, Fat 85..105, Ini 98..117, MAtk 44..64, RAtk 30..49, MDef -2..7, RDef -2..7` | — | `+1.4` | `0..7 (peak 5@21%)` | `36% / 23% / 41%` | **8.69★** | `40.2 ± 20.0` (`P95 72.0`) | `7/d` | `60c` |
| 28 | Vanilla | **Daytaler** | `daytaler_background.nut` | `+1.5` | **`1.92×`**: `HP 45..65, Res 25..45, Fat 87..106, Ini 95..115, MAtk 42..62, RAtk 27..47, MDef -2..7, RDef -2..7` | — | `+1.5` | `0..7 (peak 5@21%)` | `36% / 23% / 41%` | **8.69★** | `39.5 ± 20.6` (`P95 71.3`) | `7/d` | `60c` |
| 29 | Vanilla | **Daytaler** | `daytaler_southern_background.nut` | `+1.5` | **`1.92×`**: `HP 45..65, Res 25..45, Fat 87..106, Ini 95..115, MAtk 42..62, RAtk 27..47, MDef -2..7, RDef -2..7` | — | `+1.5` | `0..7 (peak 5@21%)` | `36% / 23% / 41%` | **8.69★** | `39.1 ± 21.2` (`P95 72.3`) | `7/d` | `60c` |
| 30 | XBE | **Cobbler** | `cobbler_background.nut` | `+3.0` | **`1.86×`**: `HP 46..64, Res 26..44, Fat 86..104, Ini 96..114, MAtk 45..63, RAtk 28..46, MDef -2..7, RDef -2..7` | Clear `Res` | `+3.0` | `0..7 (peak 5@21%)` | `38% / 23% / 39%` | **8.44★** | `40.1 ± 19.6` (`P95 71.6`) | `7/d` | `60c` |
| 31 | XBE | **Locksmith** | `locksmith_background.nut` | `+4.5` | **`1.80×`**: `HP 46..64, Res 26..44, Fat 86..104, Ini 100..118, MAtk 44..62, RAtk 28..46, MDef -2..7, RDef -2..7` | — | `+4.5` | `0..7 (peak 5@21%)` | `40% / 24% / 36%` | **8.08★** | `40.7 ± 19.8` (`P95 71.8`) | `8/d` | `60c` |
| 32 | Vanilla | **Bowyer** | `bowyer_background.nut` | `+5.0` | **`1.78×`**: `HP 46..64, Res 24..41, Fat 84..101, Ini 96..114, MAtk 43..61, RAtk 38..56, MDef -2..7, RDef -2..7` | Keep `MAtk` | `+5.0` | `0..6 (peak 4@24%)` | `34% / 22% / 44%` | **8.42★** | `41.0 ± 18.3` (`P95 69.6`) | `8/d` | `60c` |
| 33 | Vanilla | **Mason** | `mason_background.nut` | `+5.0` | **`1.78×`**: `HP 46..64, Res 26..44, Fat 91..109, Ini 96..114, MAtk 43..61, RAtk 28..46, MDef -2..7, RDef -2..7` | — | `+5.0` | `0..7 (peak 5@21%)` | `40% / 24% / 36%` | **8.08★** | `40.3 ± 19.6` (`P95 72.0`) | `8/d` | `60c` |
| 34 | Vanilla | **Vagabond** | `vagabond_background.nut` | `+5.0` | **`1.78×`**: `HP 45..62, Res 20..38, Fat 99..116, Ini 96..114, MAtk 43..61, RAtk 28..46, MDef -2..7, RDef -2..7` | — | `+5.0` | `0..7 (peak 5@21%)` | `40% / 24% / 36%` | **8.08★** | `40.8 ± 19.9` (`P95 71.9`) | `8/d` | `60c` |
| 35 | XBE | **Gardener** | `gardener_background.nut` | `+5.5` | **`1.77×`**: `HP 46..64, Res 23..41, Fat 90..108, Ini 100..118, MAtk 44..62, RAtk 28..46, MDef -2..7, RDef -2..7` | Clear `Res` | `+5.5` | `0..7 (peak 4@23%)` | `41% / 24% / 35%` | **7.88★** | `40.3 ± 19.7` (`P95 71.6`) | `8/d` | `60c` |
| 36 | Vanilla | **Deserter** | `deserter_background.nut` | `+6.1` | **`1.74×`**: `HP 46..64, Res 14..31, Fat 86..104, Ini 96..114, MAtk 48..66, RAtk 32..49, MDef 2..11, RDef 2..11` | Keep `Res` | `+6.1` | `0..6 (peak 4@25%)` | `41% / 24% / 35%` | **7.49★** | `41.4 ± 18.9` (`P95 71.7`) | `8/d` | `70c` |
| 37 | Vanilla | **Bastard** | `bastard_background.nut` | `+6.2` | **`1.74×`**: `HP 46..64, Res 21..39, Fat 86..104, Ini 96..114, MAtk 51..68, RAtk 28..46, MDef -2..7, RDef -2..7` | — | `+6.2` | `0..7 (peak 4@23%)` | `42% / 25% / 33%` | **7.75★** | `41.1 ± 19.2` (`P95 72.7`) | `8/d` | `70c` |
| 38 | Vanilla | **Juggler** | `juggler_background.nut` | `+6.2` | **`1.74×`**: `HP 41..59, Res 26..44, Fat 86..104, Ini 107..125, MAtk 43..61, RAtk 31..49, MDef -2..7, RDef -2..7` | — | `+6.2` | `0..7 (peak 4@23%)` | `42% / 25% / 33%` | **7.75★** | `39.7 ± 19.6` (`P95 72.1`) | `8/d` | `70c` |
| 39 | Vanilla | **Juggler** | `juggler_southern_background.nut` | `+6.2` | **`1.74×`**: `HP 41..59, Res 26..44, Fat 86..104, Ini 107..125, MAtk 43..61, RAtk 31..49, MDef -2..7, RDef -2..7` | — | `+6.2` | `0..7 (peak 4@23%)` | `42% / 25% / 33%` | **7.75★** | `40.1 ± 20.0` (`P95 72.2`) | `8/d` | `70c` |
| 40 | XBE | **Atilliator** | `atilliator_background.nut` | `+6.5` | **`1.73×`**: `HP 46..64, Res 24..41, Fat 84..101, Ini 96..114, MAtk 43..61, RAtk 40..57, MDef -2..7, RDef -2..7` | Keep `MAtk` | `+6.5` | `0..6 (peak 4@23%)` | `36% / 23% / 41%` | **8.12★** | `42.4 ± 17.8` (`P95 70.0`) | `8/d` | `70c` |
| 41 | XBE | **Carpenter** | `carpenter_background.nut` | `+6.5` | **`1.73×`**: `HP 50..68, Res 26..44, Fat 84..102, Ini 96..114, MAtk 46..64, RAtk 28..46, MDef -2..7, RDef -2..7` | — | `+6.5` | `0..7 (peak 4@23%)` | `42% / 25% / 33%` | **7.75★** | `41.1 ± 19.8` (`P95 73.2`) | `8/d` | `70c` |
| 42 | Vanilla | **Ratcatcher** | `ratcatcher_background.nut` | `+7.4` | **`1.69×`**: `HP 42..58, Res 27..43, Fat 87..103, Ini 113..130, MAtk 44..60, RAtk 29..45, MDef -2..7, RDef -2..7` | — | `+7.4` | `0..7 (peak 4@23%)` | `43% / 25% / 32%` | **7.52★** | `40.4 ± 18.9` (`P95 71.2`) | `8/d` | `70c` |
| 43 | Vanilla | **Disowned Noble** | `disowned_noble_background.nut` | `+7.5` | **`1.69×`**: `HP 47..63, Res 23..40, Fat 79..96, Ini 97..113, MAtk 53..69, RAtk 33..50, MDef 0..8, RDef -2..7` | — | `+7.5` | `0..7 (peak 4@23%)` | `43% / 25% / 32%` | **7.52★** | `42.2 ± 18.2` (`P95 71.1`) | `8/d` | `70c` |
| 44 | XBE | **Hangman** | `hangman_background.nut` | `+7.7` | **`1.68×`**: `HP 51..67, Res 31..47, Fat 87..103, Ini 96..112, MAtk 44..60, RAtk 29..45, MDef -2..7, RDef -2..7` | — | `+7.7` | `0..7 (peak 4@23%)` | `44% / 25% / 31%` | **7.39★** | `41.5 ± 17.9` (`P95 71.1`) | `8/d` | `70c` |
| 45 | Vanilla | **Miller** | `miller_background.nut` | `+8.0` | **`1.67×`**: `HP 48..65, Res 27..43, Fat 93..110, Ini 97..113, MAtk 44..60, RAtk 29..45, MDef -2..7, RDef -2..7` | — | `+8.0` | `0..7 (peak 4@23%)` | `44% / 25% / 31%` | **7.39★** | `40.9 ± 18.3` (`P95 70.8`) | `8/d` | `70c` |
| 46 | XBE | **Surgeon** | `surgeon_background.nut` | `+10.0` | **`1.59×`**: `HP 47..63, Res 31..47, Fat 87..103, Ini 97..113, MAtk 48..64, RAtk 29..45, MDef -1..6, RDef -1..6` | — | `+10.0` | `0..7 (peak 4@23%)` | `46% / 26% / 28%` | **6.97★** | `41.8 ± 17.8` (`P95 71.9`) | `8/d` | `70c` |
| 47 | Vanilla | **Miner** | `miner_background.nut` | `+10.2` | **`1.58×`**: `HP 57..73, Res 34..49, Fat 77..93, Ini 97..113, MAtk 47..62, RAtk 29..45, MDef -1..6, RDef -1..6` | — | `+10.2` | `0..7 (peak 4@23%)` | `46% / 26% / 28%` | **6.97★** | `41.6 ± 18.0` (`P95 71.2`) | `8/d` | `70c` |
| 48 | Vanilla | **Pimp** | `pimp_background.nut` | `+10.2` | **`1.58×`**: `HP 47..63, Res 32..48, Fat 87..103, Ini 101..116, MAtk 39..55, RAtk 29..45, MDef 3..11, RDef 3..11` | — | `+10.2` | `0..7 (peak 4@23%)` | `46% / 26% / 28%` | **6.97★** | `40.9 ± 18.8` (`P95 72.4`) | `8/d` | `70c` |
| 49 | Vanilla | **Belly Dancer** | `belly_dancer_background.nut` | `+10.5` | **`1.57×`**: `HP 42..58, Res 22..38, Fat 82..98, Ini 107..123, MAtk 54..70, RAtk 34..50, MDef -1..6, RDef -1..6` | Clear `HP, Fat, RDef, Res` | `+10.5` | `0..7 (peak 4@24%)` | `47% / 26% / 27%` | **6.84★** | `41.2 ± 17.4` (`P95 70.3`) | `9/d` | `70c` |
| 50 | XBE | **Drifter** | `drifter_background.nut` | `+10.9` | **`1.55×`**: `HP 46..62, Res 27..43, Fat 94..110, Ini 102..118, MAtk 44..60, RAtk 29..45, MDef -1..6, RDef 0..8` | — | `+10.9` | `0..7 (peak 4@24%)` | `47% / 26% / 27%` | **6.84★** | `41.6 ± 17.7` (`P95 70.4`) | `9/d` | `70c` |
| 51 | Vanilla | **Shepherd** | `shepherd_background.nut` | `+11.0` | **`1.55×`**: `HP 47..63, Res 30..45, Fat 90..105, Ini 97..113, MAtk 44..60, RAtk 35..51, MDef -1..6, RDef -1..6` | — | `+11.0` | `0..7 (peak 4@24%)` | `47% / 26% / 27%` | **6.84★** | `43.3 ± 17.1` (`P95 70.4`) | `9/d` | `70c` |
| 52 | Vanilla | **Shepherd** | `shepherd_southern_background.nut` | `+11.0` | **`1.55×`**: `HP 47..63, Res 30..45, Fat 90..105, Ini 97..113, MAtk 44..60, RAtk 35..51, MDef -1..6, RDef -1..6` | — | `+11.0` | `0..7 (peak 4@24%)` | `47% / 26% / 27%` | **6.84★** | `43.5 ± 17.6` (`P95 72.0`) | `9/d` | `70c` |
| 53 | XBE | **Blacksmith** | `blacksmith_background.nut` | `+11.0` | **`1.55×`**: `HP 51..67, Res 27..43, Fat 91..107, Ini 97..113, MAtk 46..62, RAtk 29..45, MDef -1..6, RDef -1..6` | — | `+11.0` | `0..7 (peak 4@24%)` | `47% / 26% / 27%` | **6.84★** | `42.2 ± 18.1` (`P95 71.8`) | `9/d` | `70c` |
| 54 | Vanilla | **Fisherman** | `fisherman_background.nut` | `+11.9` | **`1.51×`**: `HP 50..65, Res 30..45, Fat 92..108, Ini 100..115, MAtk 44..60, RAtk 29..45, MDef -1..6, RDef -1..6` | — | `+11.9` | `0..7 (peak 4@24%)` | `48% / 27% / 25%` | **6.62★** | `42.0 ± 17.1` (`P95 69.5`) | `9/d` | `80c` |
| 55 | Vanilla | **Fisherman** | `fisherman_southern_background.nut` | `+11.9` | **`1.51×`**: `HP 50..65, Res 30..45, Fat 92..108, Ini 100..115, MAtk 44..60, RAtk 29..45, MDef -1..6, RDef -1..6` | — | `+11.9` | `0..7 (peak 4@24%)` | `48% / 27% / 25%` | **6.62★** | `42.7 ± 17.6` (`P95 70.9`) | `9/d` | `80c` |
| 56 | Vanilla | **Flagellant** | `flagellant_background.nut` | `+12.0` | **`1.51×`**: `HP 40..55, Res 39..55, Fat 95..110, Ini 97..113, MAtk 44..60, RAtk 29..45, MDef -1..6, RDef -1..6` | — | `+12.0` | `0..7 (peak 4@24%)` | `48% / 27% / 25%` | **6.62★** | `42.8 ± 17.6` (`P95 71.1`) | `9/d` | `80c` |
| 57 | Vanilla | **Butcher** | `butcher_background.nut` | `+12.2` | **`1.50×`**: `HP 50..64, Res 34..48, Fat 90..104, Ini 98..112, MAtk 47..62, RAtk 28..43, MDef -1..6, RDef -1..6` | Keep `RAtk` | `+12.2` | `0..6 (peak 4@25%)` | `48% / 27% / 25%` | **6.37★** | `42.9 ± 17.4` (`P95 70.9`) | `9/d` | `80c` |
| 58 | Vanilla | **Butcher** | `butcher_southern_background.nut` | `+12.2` | **`1.50×`**: `HP 50..64, Res 34..48, Fat 90..104, Ini 98..112, MAtk 47..62, RAtk 28..43, MDef -1..6, RDef -1..6` | Keep `RAtk` | `+12.2` | `0..6 (peak 4@25%)` | `48% / 27% / 25%` | **6.37★** | `42.8 ± 17.0` (`P95 70.7`) | `9/d` | `80c` |
| 59 | XBE | **Torturer** | `torturer_background.nut` | `+12.6` | **`1.49×`**: `HP 55..70, Res 28..42, Fat 90..105, Ini 98..112, MAtk 48..63, RAtk 30..44, MDef -3..5, RDef -3..5` | — | `+12.6` | `0..7 (peak 4@25%)` | `49% / 27% / 24%` | **6.44★** | `42.4 ± 17.2` (`P95 70.3`) | `9/d` | `80c` |
| 60 | XBE | **Fletcher** | `fletcher_background.nut` | `+13.1` | **`1.46×`**: `HP 46..60, Res 26..40, Fat 88..102, Ini 105..120, MAtk 45..59, RAtk 41..56, MDef -1..6, RDef -1..6` | Clear `HP, Res` | `+13.1` | `0..7 (peak 4@25%)` | `49% / 27% / 24%` | **6.44★** | `42.8 ± 16.7` (`P95 69.7`) | `9/d` | `80c` |
| 61 | Vanilla | **Gravedigger** | `gravedigger_background.nut` | `+13.2` | **`1.46×`**: `HP 50..64, Res 34..48, Fat 94..108, Ini 95..110, MAtk 45..59, RAtk 30..44, MDef -1..6, RDef -1..6` | — | `+13.2` | `0..7 (peak 4@25%)` | `50% / 27% / 23%` | **6.30★** | `42.6 ± 17.0` (`P95 69.8`) | `9/d` | `80c` |
| 62 | XBE | **Druid** | `druid_background.nut` | `+13.5` | **`1.45×`**: `HP 53..67, Res 34..48, Fat 90..105, Ini 98..112, MAtk 45..59, RAtk 30..44, MDef -1..6, RDef -1..6` | — | `+13.5` | `0..7 (peak 4@25%)` | `50% / 27% / 23%` | **6.30★** | `43.3 ± 16.5` (`P95 70.2`) | `9/d` | `80c` |
| 63 | XBE | **Dissenter** | `dissenter_background.nut` | `+14.5` | **`1.41×`**: `HP 48..62, Res 47..61, Fat 88..102, Ini 98..112, MAtk 45..59, RAtk 30..44, MDef -4..3, RDef -1..6` | — | `+14.5` | `0..7 (peak 4@25%)` | `51% / 27% / 22%` | **6.09★** | `43.4 ± 16.5` (`P95 70.0`) | `9/d` | `80c` |
| 64 | Vanilla | **Poacher** | `poacher_background.nut` | `+14.9` | **`1.39×`**: `HP 48..62, Res 28..42, Fat 90..103, Ini 100..114, MAtk 46..60, RAtk 41..55, MDef -1..6, RDef -1..6` | — | `+14.9` | `0..7 (peak 4@25%)` | `51% / 27% / 22%` | **6.09★** | `43.1 ± 15.8` (`P95 69.1`) | `9/d` | `80c` |
| 65 | XBE | **Con Artist** | `con_artist_background.nut` | `+15.4` | **`1.37×`**: `HP 48..62, Res 28..42, Fat 88..102, Ini 103..117, MAtk 49..63, RAtk 32..46, MDef 1..8, RDef 1..8` | — | `+15.4` | `0..7 (peak 4@25%)` | `52% / 28% / 20%` | **5.91★** | `42.7 ± 16.0` (`P95 68.4`) | `9/d` | `80c` |
| 66 | Vanilla | **Cultist** | `cultist_background.nut` | `+15.5` | **`1.37×`**: `HP 48..62, Res 41..54, Fat 91..105, Ini 98..112, MAtk 45..59, RAtk 30..44, MDef -1..6, RDef -1..6` | — | `+15.5` | `0..7 (peak 4@25%)` | `52% / 28% / 20%` | **5.91★** | `43.5 ± 16.5` (`P95 70.6`) | `9/d` | `80c` |
| 67 | Vanilla | **Caravan Hand** | `caravan_hand_background.nut` | `+16.0` | **`1.35×`**: `HP 52..66, Res 31..45, Fat 94..108, Ini 98..112, MAtk 47..61, RAtk 30..44, MDef -1..6, RDef -1..6` | — | `+16.0` | `0..7 (peak 4@25%)` | `52% / 28% / 20%` | **5.91★** | `44.8 ± 16.5` (`P95 71.5`) | `9/d` | `90c` |
| 68 | Vanilla | **Caravan Hand** | `caravan_hand_southern_background.nut` | `+16.0` | **`1.35×`**: `HP 52..66, Res 31..45, Fat 94..108, Ini 98..112, MAtk 47..61, RAtk 30..44, MDef -1..6, RDef -1..6` | — | `+16.0` | `0..7 (peak 4@25%)` | `52% / 28% / 20%` | **5.91★** | `43.8 ± 16.8` (`P95 70.9`) | `9/d` | `90c` |
| 69 | XBE | **Barkeep** | `barkeep_background.nut` | `+16.0` | **`1.35×`**: `HP 56..69, Res 28..42, Fat 92..106, Ini 93..107, MAtk 47..61, RAtk 30..44, MDef 1..8, RDef -1..6` | — | `+16.0` | `0..7 (peak 4@25%)` | `52% / 28% / 20%` | **5.91★** | `43.4 ± 16.1` (`P95 69.6`) | `9/d` | `90c` |
| 70 | XBE | **Roofer** | `roofer_background.nut` | `+16.1` | **`1.35×`**: `HP 50..64, Res 28..42, Fat 96..109, Ini 95..109, MAtk 45..59, RAtk 30..44, MDef 4..11, RDef -1..6` | — | `+16.1` | `0..7 (peak 3@25%)` | `53% / 28% / 19%` | **5.81★** | `43.5 ± 16.4` (`P95 70.4`) | `9/d` | `90c` |
| 71 | Vanilla | **Graverobber** | `graverobber_background.nut` | `+16.4` | **`1.33×`**: `HP 48..62, Res 35..48, Fat 93..107, Ini 100..114, MAtk 47..60, RAtk 30..44, MDef 0..6, RDef 0..6` | — | `+16.4` | `0..7 (peak 3@25%)` | `53% / 28% / 19%` | **5.81★** | `43.3 ± 16.0` (`P95 69.9`) | `10/d` | `90c` |
| 72 | Vanilla | **Houndmaster** | `houndmaster_background.nut` | `+16.4` | **`1.33×`**: `HP 51..64, Res 33..47, Fat 91..104, Ini 101..114, MAtk 45..59, RAtk 30..44, MDef 2..9, RDef -1..6` | — | `+16.4` | `0..7 (peak 3@25%)` | `53% / 28% / 19%` | **5.81★** | `43.6 ± 15.9` (`P95 70.1`) | `10/d` | `90c` |
| 73 | XBE | **Arbalester** | `arbalester_background.nut` | `+16.6` | **`1.32×`**: `HP 46..59, Res 28..42, Fat 92..106, Ini 98..112, MAtk 45..59, RAtk 44..58, MDef -1..6, RDef 1..7` | Keep `MAtk` *(clear `MDef`)* | `+16.6` | `0..6 (peak 4@25%)` | `50% / 27% / 23%` | **6.11★** | `44.4 ± 14.9` (`P95 69.6`) | `10/d` | `90c` |
| 74 | Vanilla | **Gambler** | `gambler_background.nut` | `+18.0` | **`1.27×`**: `HP 47..59, Res 41..53, Fat 83..96, Ini 110..122, MAtk 46..58, RAtk 31..43, MDef 0..7, RDef 4..11` | — | `+18.0` | `0..7 (peak 3@26%)` | `54% / 28% / 18%` | **5.56★** | `44.4 ± 15.3` (`P95 69.9`) | `10/d` | `90c` |
| 75 | Vanilla | **Gambler** | `gambler_southern_background.nut` | `+18.0` | **`1.27×`**: `HP 47..59, Res 41..53, Fat 83..96, Ini 110..122, MAtk 46..58, RAtk 31..43, MDef 0..7, RDef 4..11` | — | `+18.0` | `0..7 (peak 3@26%)` | `54% / 28% / 18%` | **5.56★** | `43.9 ± 15.7` (`P95 70.9`) | `10/d` | `90c` |
| 76 | XBE | **Falconer** | `falconer_background.nut` | `+18.0` | **`1.27×`**: `HP 46..58, Res 29..41, Fat 89..101, Ini 116..128, MAtk 46..58, RAtk 40..52, MDef -3..3, RDef 3..10` | — | `+18.0` | `0..7 (peak 3@26%)` | `54% / 28% / 18%` | **5.56★** | `44.0 ± 14.9` (`P95 69.5`) | `10/d` | `90c` |
| 77 | Vanilla | **Messenger** | `messenger_background.nut` | `+18.8` | **`1.24×`**: `HP 49..61, Res 31..44, Fat 101..114, Ini 99..111, MAtk 46..58, RAtk 31..43, MDef 0..7, RDef 2..9` | — | `+18.8` | `0..7 (peak 3@27%)` | `55% / 29% / 16%` | **5.35★** | `43.7 ± 14.7` (`P95 67.4`) | `10/d` | `90c` |
| 78 | Vanilla | **Retired Soldier** | `retired_soldier_background.nut` | `+20.1` | **`1.19×`**: `HP 37..48, Res 41..52, Fat 79..91, Ini 92..103, MAtk 58..69, RAtk 34..45, MDef 6..12, RDef 6..12` | — | `+20.1` | `0..7 (peak 3@28%)` | `57% / 29% / 14%` | **5.09★** | `43.6 ± 14.1` (`P95 66.7`) | `10/d` | `100c` |
| 79 | Vanilla | **Anatomist** | `anatomist_background.nut` | `+20.5` | **`1.17×`**: `HP 45..57, Res 39..51, Fat 87..98, Ini 99..111, MAtk 53..65, RAtk 40..52, MDef 0..6, RDef 0..6` | — | `+20.5` | `0..7 (peak 3@28%)` | `57% / 29% / 14%` | **5.09★** | `45.9 ± 14.0` (`P95 69.4`) | `10/d` | `100c` |
| 80 | XBE | **Town Watchman** | `town_watchman_background.nut` | `+20.8` | **`1.16×`**: `HP 51..62, Res 30..42, Fat 94..106, Ini 102..113, MAtk 51..63, RAtk 38..49, MDef 0..5, RDef 0..5` | — | `+20.8` | `0..7 (peak 3@30%)` | `58% / 29% / 13%` | **4.94★** | `44.8 ± 14.1` (`P95 68.3`) | `10/d` | `100c` |
| 81 | XBE | **Myrmidon** | `myrmidon_background.nut` | `+21.3` | **`1.14×`**: `HP 53..65, Res 25..37, Fat 93..105, Ini 102..114, MAtk 51..63, RAtk 38..50, MDef 1..7, RDef 1..7` | — | `+21.3` | `0..7 (peak 3@30%)` | `58% / 29% / 13%` | **4.94★** | `46.1 ± 14.2` (`P95 69.8`) | `10/d` | `100c` |
| 82 | XBE | **Pirate** | `pirate_background.nut` | `+21.5` | **`1.13×`**: `HP 49..61, Res 28..39, Fat 94..106, Ini 104..116, MAtk 51..62, RAtk 31..43, MDef 3..8, RDef 4..9` | — | `+21.5` | `0..6 (peak 3@30%)` | `58% / 30% / 12%` | **4.77★** | `44.5 ± 13.7` (`P95 66.9`) | `10/d` | `100c` |
| 83 | Vanilla | **Witchhunter** | `witchhunter_background.nut` | `+22.5` | **`1.09×`**: `HP 50..60, Res 41..51, Fat 90..100, Ini 100..110, MAtk 47..57, RAtk 43..54, MDef 0..5, RDef 0..5` | — | `+22.5` | `0..6 (peak 3@31%)` | `59% / 30% / 11%` | **4.65★** | `46.3 ± 12.8` (`P95 67.8`) | `11/d` | `100c` |
| 84 | XBE | **Master Archer** | `master_archer_background.nut` | `+22.8` | **`1.08×`**: `HP 34..44, Res 34..44, Fat 81..92, Ini 110..120, MAtk 37..48, RAtk 62..72, MDef -5..0, RDef 6..12` | Keep `MAtk` *(clear `MDef`)* | `+22.8` | `0..6 (peak 3@28%)` | `57% / 29% / 14%` | **5.04★** | `45.1 ± 11.6` (`P95 64.4`) | `11/d` | `100c` |
| 85 | Vanilla | **Militia** | `militia_background.nut` | `+23.3` | **`1.06×`**: `HP 50..60, Res 34..44, Fat 94..104, Ini 100..110, MAtk 52..62, RAtk 37..48, MDef 2..7, RDef 2..7` | — | `+23.3` | `0..6 (peak 3@32%)` | `60% / 30% / 10%` | **4.50★** | `45.9 ± 12.5` (`P95 66.4`) | `11/d` | `110c` |
| 86 | Vanilla | **Farmhand** | `farmhand_background.nut` | `+23.5` | **`1.05×`**: `HP 61..71, Res 27..38, Fat 105..115, Ini 100..110, MAtk 47..57, RAtk 32..42, MDef 0..5, RDef 0..5` | — | `+23.5` | `0..6 (peak 3@32%)` | `60% / 30% / 10%` | **4.50★** | `46.7 ± 13.1` (`P95 68.1`) | `11/d` | `110c` |
| 87 | Vanilla | **Companion** *(Origin)* | `companion_ranged_background.nut` | `+24.0` | **`1.03×`**: `HP 50..60, Res 35..45, Fat 90..100, Ini 105..115, MAtk 49..60, RAtk 45..55, MDef 0..5, RDef 0..5` | Keep `MAtk` *(clear `HP, MDef`)* | `+24.0` | `0..6 (peak 3@30%)` | `58% / 30% / 12%` | **4.77★** | `45.6 ± 12.1` (`P95 65.5`) | `11/d` | `110c` |
| 88 | Vanilla | **Companion** *(Origin)* | `companion_ranged_southern_background.nut` | `+24.0` | **`1.03×`**: `HP 50..60, Res 35..45, Fat 90..100, Ini 105..115, MAtk 49..60, RAtk 45..55, MDef 0..5, RDef 0..5` | Keep `MAtk` *(clear `HP, MDef`)* | `+24.0` | `0..6 (peak 3@30%)` | `58% / 30% / 12%` | **4.77★** | `46.2 ± 12.4` (`P95 66.7`) | `11/d` | `110c` |
| 89 | Vanilla | **Thief** | `thief_background.nut` | `+25.4` | **`0.98×`**: `HP 50..60, Res 33..42, Fat 90..100, Ini 111..121, MAtk 47..57, RAtk 32..42, MDef 7..11, RDef 7..11` | — | `+25.4` | `0..6 (peak 3@33%)` | `62% / 28% / 10%` | **4.14★** | `45.9 ± 12.6` (`P95 66.6`) | `11/d` | `110c` |
| 90 | Vanilla | **Thief** | `thief_southern_background.nut` | `+25.4` | **`0.98×`**: `HP 50..60, Res 33..42, Fat 90..100, Ini 111..121, MAtk 47..57, RAtk 32..42, MDef 7..11, RDef 7..11` | — | `+25.4` | `0..6 (peak 3@33%)` | `62% / 28% / 10%` | **4.14★** | `45.4 ± 13.2` (`P95 67.2`) | `11/d` | `110c` |
| 91 | Vanilla | **Manhunter** | `manhunter_background.nut` | `+25.7` | **`0.96×`**: `HP 53..62, Res 36..46, Fat 94..104, Ini 104..114, MAtk 52..62, RAtk 32..42, MDef 2..7, RDef -1..4` | — | `+25.7` | `0..6 (peak 3@33%)` | `62% / 28% / 10%` | **4.14★** | `46.4 ± 12.4` (`P95 67.8`) | `11/d` | `110c` |
| 92 | Vanilla | **Brawler** | `brawler_background.nut` | `+26.6` | **`0.93×`**: `HP 58..67, Res 36..46, Fat 98..107, Ini 103..112, MAtk 50..59, RAtk 32..42, MDef 0..5, RDef 0..5` | Keep `RAtk` | `+26.6` | `0..6 (peak 3@32%)` | `64% / 27% / 9%` | **3.86★** | `46.6 ± 12.3` (`P95 67.2`) | `11/d` | `120c` |
| 93 | Vanilla | **Nomad** | `nomad_ranged_background.nut` | `+27.7` | **`0.88×`**: `HP 51..59, Res 29..38, Fat 92..100, Ini 101..109, MAtk 52..60, RAtk 47..56, MDef 4..9, RDef 6..10` | — | `+27.7` | `0..6 (peak 3@32%)` | `64% / 27% / 9%` | **3.86★** | `47.4 ± 11.8` (`P95 67.2`) | `11/d` | `120c` |
| 94 | Vanilla | **Lumberjack** | `lumberjack_background.nut` | `+28.0` | **`0.87×`**: `HP 61..69, Res 33..42, Fat 103..112, Ini 98..107, MAtk 50..59, RAtk 33..41, MDef 0..5, RDef 0..5` | — | `+28.0` | `0..5 (peak 3@32%)` | `65% / 27% / 8%` | **3.66★** | `47.2 ± 11.7` (`P95 66.5`) | `11/d` | `120c` |
| 95 | XBE | **Skirmisher** | `skirmisher_background.nut` | `+28.1` | **`0.87×`**: `HP 48..57, Res 29..37, Fat 98..106, Ini 111..119, MAtk 53..61, RAtk 44..52, MDef 1..6, RDef 2..6` | Clear `Res` | `+28.1` | `0..5 (peak 3@32%)` | `65% / 27% / 8%` | **3.66★** | `46.6 ± 11.2` (`P95 64.9`) | `11/d` | `120c` |
| 96 | Vanilla | **Nomad** | `nomad_background.nut` | `+29.9` | **`0.80×`**: `HP 51..59, Res 30..37, Fat 92..100, Ini 101..109, MAtk 59..67, RAtk 36..43, MDef 6..10, RDef 6..10` | — | `+29.9` | `0..5 (peak 2@35%)` | `67% / 25% / 8%` | **3.36★** | `47.4 ± 11.1` (`P95 66.3`) | `12/d` | `130c` |
| 97 | Vanilla | **Raider** | `raider_background.nut` | `+29.9` | **`0.80×`**: `HP 51..59, Res 30..37, Fat 92..100, Ini 101..109, MAtk 59..67, RAtk 36..43, MDef 6..10, RDef 6..10` | — | `+29.9` | `0..5 (peak 2@35%)` | `67% / 25% / 8%` | **3.36★** | `47.6 ± 10.8` (`P95 65.8`) | `12/d` | `130c` |
| 98 | Vanilla | **Hunter** | `hunter_background.nut` | `+30.0` | **`0.79×`**: `HP 51..59, Res 34..41, Fat 97..105, Ini 104..111, MAtk 48..56, RAtk 52..59, MDef 1..4, RDef 2..6` | — | `+30.0` | `0..5 (peak 2@35%)` | `67% / 25% / 8%` | **3.36★** | `48.2 ± 10.7` (`P95 66.7`) | `12/d` | `130c` |
| 99 | Vanilla | **Companion** *(Origin)* | `companion_2h_background.nut` | `+32.8` | **`0.69×`**: `HP 59..66, Res 39..46, Fat 97..103, Ini 99..106, MAtk 56..63, RAtk 34..40, MDef 2..5, RDef 2..5` | Keep `RAtk` *(clear `RDef`)* | `+32.8` | `0..5 (peak 2@39%)` | `70% / 23% / 7%` | **2.96★** | `48.2 ± 10.7` (`P95 67.2`) | `12/d` | `140c` |
| 100 | Vanilla | **Companion** *(Origin)* | `companion_2h_southern_background.nut` | `+32.8` | **`0.69×`**: `HP 59..66, Res 39..46, Fat 97..103, Ini 99..106, MAtk 56..63, RAtk 34..40, MDef 2..5, RDef 2..5` | Keep `RAtk` *(clear `RDef`)* | `+32.8` | `0..5 (peak 2@39%)` | `70% / 23% / 7%` | **2.96★** | `48.6 ± 10.4` (`P95 66.6`) | `12/d` | `140c` |
| 101 | Vanilla | **Executioner** | `executioner_background.nut` | `+33.9` | **`0.64×`**: `HP 60..67, Res 43..49, Fat 103..110, Ini 97..103, MAtk 54..64, RAtk 31..38, MDef -2..2, RDef -4..-1` | Keep `RAtk` | `+33.9` | `0..4 (peak 2@42%)` | `71% / 22% / 7%` | **2.72★** | `47.6 ± 10.8` (`P95 66.0`) | `12/d` | `140c` |
| 102 | Vanilla | **Executioner** | `executioner_southern_background.nut` | `+33.9` | **`0.64×`**: `HP 60..67, Res 43..49, Fat 103..110, Ini 97..103, MAtk 54..64, RAtk 31..38, MDef -2..2, RDef -4..-1` | Keep `RAtk` | `+33.9` | `0..4 (peak 2@42%)` | `71% / 22% / 7%` | **2.72★** | `47.6 ± 10.8` (`P95 66.0`) | `12/d` | `140c` |
| 103 | Reforged | **Old Swordmaster** | `rf_old_swordmaster_background.nut` | `+34.2` | **`0.63×`**: `HP 40..46, Res 43..49, Fat 79..86, Ini 92..98, MAtk 71..78, RAtk 29..35, MDef 13..17, RDef 1..4` | Keep `RAtk` *(clear `RDef`)* | `+34.2` | `0..4 (peak 2@42%)` | `71% / 22% / 7%` | **2.72★** | `49.0 ± 10.2` (`P95 67.0`) | `12/d` | `140c` |
| 104 | Vanilla | **Swordmaster** | `swordmaster_background.nut` | `+34.2` | **`0.63×`**: `HP 40..46, Res 43..49, Fat 79..86, Ini 92..98, MAtk 71..78, RAtk 29..35, MDef 13..17, RDef 1..4` | Keep `RAtk` | `+34.2` | `0..4 (peak 2@42%)` | `71% / 22% / 7%` | **2.72★** | `48.6 ± 9.8` (`P95 65.4`) | `12/d` | `140c` |
| 105 | Vanilla | **Squire** | `squire_background.nut` | `+36.0` | **`0.56×`**: `HP 52..58, Res 44..50, Fat 98..104, Ini 102..108, MAtk 54..62, RAtk 42..47, MDef 3..6, RDef 3..6` | — | `+36.0` | `0..4 (peak 2@44%)` | `73% / 21% / 6%` | **2.50★** | `50.0 ± 9.4` (`P95 66.2`) | `13/d` | `150c` |
| 106 | XBE | **Berserker** | `berserker_background.nut` | `+36.8` | **`0.52×`**: `HP 64..70, Res 45..50, Fat 112..117, Ini 97..103, MAtk 53..59, RAtk 28..34, MDef -1..2, RDef -8..-5` | — | `+36.8` | `0..4 (peak 2@44%)` | `74% / 21% / 5%` | **2.36★** | `51.0 ± 9.5` (`P95 68.0`) | `13/d` | `160c` |
| 107 | Vanilla | **Beast Slayer** | `beast_hunter_background.nut` | `+37.0` | **`0.52×`**: `HP 54..59, Res 44..49, Fat 98..104, Ini 108..114, MAtk 54..60, RAtk 43..49, MDef 1..4, RDef 1..4` | — | `+37.0` | `0..4 (peak 2@44%)` | `74% / 21% / 5%` | **2.36★** | `50.0 ± 8.5` (`P95 64.6`) | `13/d` | `160c` |
| 108 | Vanilla | **Wildman** | `wildman_background.nut` | `+37.8` | **`0.49×`**: `HP 64..68, Res 44..48, Fat 113..118, Ini 98..102, MAtk 53..57, RAtk 32..37, MDef -1..1, RDef -4..-1` | — | `+37.8` | `0..4 (peak 2@45%)` | `74% / 20% / 6%` | **2.27★** | `50.3 ± 8.7` (`P95 66.4`) | `13/d` | `160c` |
| 109 | XBE | **Bounty Hunter** | `bounty_hunter_background.nut` | `+37.8` | **`0.49×`**: `HP 53..57, Res 36..40, Fat 96..100, Ini 112..116, MAtk 60..65, RAtk 43..47, MDef 4..7, RDef 1..4` | — | `+37.8` | `0..4 (peak 2@45%)` | `74% / 20% / 6%` | **2.27★** | `49.8 ± 8.6` (`P95 65.4`) | `13/d` | `160c` |
| 110 | Vanilla | **Assassin** | `assassin_southern_background.nut` | `+37.9` | **`0.48×`**: `HP 48..52, Res 43..47, Fat 88..92, Ini 120..125, MAtk 60..64, RAtk 35..39, MDef 8..10, RDef 1..4` | Clear `HP, Fat` | `+37.9` | `0..4 (peak 2@45%)` | `74% / 20% / 6%` | **2.27★** | `50.4 ± 8.2` (`P95 65.3`) | `13/d` | `160c` |
| 111 | Vanilla | **Companion** *(Origin)* | `companion_1h_background.nut` | `+38.0` | **`0.48×`**: `HP 53..57, Res 40..45, Fat 98..102, Ini 103..107, MAtk 57..62, RAtk 40..44, MDef 6..9, RDef 6..9` | Keep `RAtk` | `+38.0` | `0..4 (peak 2@45%)` | `74% / 20% / 6%` | **2.27★** | `50.2 ± 8.5` (`P95 65.2`) | `13/d` | `160c` |
| 112 | Vanilla | **Companion** *(Origin)* | `companion_1h_southern_background.nut` | `+38.0` | **`0.48×`**: `HP 53..57, Res 40..45, Fat 98..102, Ini 103..107, MAtk 57..62, RAtk 40..44, MDef 6..9, RDef 6..9` | Keep `RAtk` | `+38.0` | `0..4 (peak 2@45%)` | `74% / 20% / 6%` | **2.27★** | `50.1 ± 8.6` (`P95 65.3`) | `13/d` | `160c` |
| 113 | XBE | **Bodyguard** | `bodyguard_background.nut` | `+39.1` | **`0.43×`**: `HP 61..65, Res 38..42, Fat 98..102, Ini 88..92, MAtk 52..56, RAtk 31..35, MDef 15..18, RDef 9..11` | Clear `Ini` | `+39.1` | `0..4 (peak 2@43%)` | `76% / 19% / 5%` | **2.05★** | `50.2 ± 8.1` (`P95 64.7`) | `13/d` | `170c` |
| 114 | Vanilla | **Assassin** | `assassin_background.nut` | `+39.4` | **`0.42×`**: `HP 48..52, Res 43..47, Fat 88..92, Ini 120..125, MAtk 61..65, RAtk 35..39, MDef 8..10, RDef 1..4` | Clear `HP, Fat, RDef, Res` | `+39.4` | `0..4 (peak 2@43%)` | `76% / 19% / 5%` | **2.05★** | `50.5 ± 8.0` (`P95 65.6`) | `13/d` | `170c` |
| 115 | Vanilla | **Barbarian** | `barbarian_background.nut` | `+39.4` | **`0.42×`**: `HP 60..65, Res 40..45, Fat 100..105, Ini 110..115, MAtk 57..62, RAtk 35..39, MDef 1..4, RDef 1..4` | — | `+39.4` | `0..4 (peak 2@43%)` | `76% / 19% / 5%` | **2.05★** | `50.4 ± 8.3` (`P95 64.8`) | `13/d` | `170c` |
| 116 | XBE | **Lancer** | `lancer_background.nut` | `+39.5` | **`0.42×`**: `HP 53..57, Res 39..44, Fat 99..103, Ini 108..112, MAtk 61..66, RAtk 35..39, MDef 4..7, RDef 3..6` | Keep `RAtk` *(clear `RDef`)* | `+39.5` | `0..4 (peak 2@43%)` | `76% / 19% / 5%` | **2.05★** | `50.8 ± 8.3` (`P95 65.6`) | `13/d` | `170c` |
| 117 | Vanilla | **Gladiator** | `gladiator_background.nut` | `+41.1` | **`0.36×`**: `HP 53..57, Res 38..42, Fat 93..97, Ini 103..107, MAtk 62..65, RAtk 42..46, MDef 8..10, RDef 8..10` | — | `+41.1` | `0..3 (peak 1@45%)` | `78% / 18% / 4%` | **1.80★** | `51.2 ± 7.1` (`P95 64.0`) | `14/d` | `180c` |
| 118 | Vanilla | **Gladiator** | `gladiator_origin_background.nut` | `+41.1` | **`0.36×`**: `HP 53..57, Res 38..42, Fat 93..97, Ini 103..107, MAtk 62..65, RAtk 42..46, MDef 8..10, RDef 8..10` | — | `+41.1` | `0..3 (peak 1@45%)` | `78% / 18% / 4%` | **1.80★** | `50.7 ± 7.2` (`P95 64.2`) | `14/d` | `180c` |
| 119 | Vanilla | **Gladiator** | `old_gladiator_background.nut` | `+41.1` | **`0.36×`**: `HP 53..57, Res 38..42, Fat 93..97, Ini 103..107, MAtk 62..65, RAtk 42..46, MDef 8..10, RDef 8..10` | — | `+41.1` | `0..3 (peak 1@45%)` | `78% / 18% / 4%` | **1.80★** | `50.9 ± 7.4` (`P95 64.4`) | `14/d` | `180c` |
| 120 | Vanilla | **Adventurous Noble** | `adventurous_noble_background.nut` | `+42.5` | **`0.32×`** *(mid ×0.97)*: `HP 53..57, Res 50..54, Fat 96..99, Ini 103..107, MAtk 60..64, RAtk 35..39, MDef 8..10, RDef -6..-4` | — | `+42.0` | `0..3 (peak 1@50%)` | `78% / 17% / 5%` | **1.73★** | `51.5 ± 7.2` (`P95 65.0`) | `14/d` | `180c` |
| 121 | XBE | **Outlander** | `outlander_background.nut` | `+42.8` | **`0.33×`** *(mid ×0.95)*: `HP 56..60, Res 38..42, Fat 98..102, Ini 113..117, MAtk 60..63, RAtk 41..45, MDef 3..5, RDef 3..5` | — | `+41.7` | `0..3 (peak 1@50%)` | `78% / 17% / 5%` | **1.73★** | `51.0 ± 7.0` (`P95 63.6`) | `14/d` | `180c` |
| 122 | Vanilla | **Converted Crusader** | `crucified_background.nut` | `+43.5` | **`0.30×`** *(mid ×0.95)*: `HP 53..57, Res 38..42, Fat 93..97, Ini 103..107, MAtk 61..65, RAtk 46..49, MDef 8..10, RDef 8..10` | — | `+42.4` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `51.1 ± 6.9` (`P95 63.6`) | `14/d` | `180c` |
| 123 | Vanilla | **Sellsword** | `sellsword_background.nut` | `+43.5` | **`0.30×`** *(mid ×0.95)*: `HP 53..57, Res 38..42, Fat 93..97, Ini 103..107, MAtk 61..65, RAtk 46..49, MDef 8..10, RDef 8..10` | — | `+42.4` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `51.0 ± 6.9` (`P95 63.6`) | `14/d` | `180c` |
| 124 | Vanilla | **Crusader** | `crusader_background.nut` | `+49.1` | **`0.27×`** *(mid ×0.85)*: `HP 63..65, Res 49..51, Fat 103..105, Ini 104..106, MAtk 60..62, RAtk 28..31, MDef 2..3, RDef -1..1` | Keep `RAtk` *(clear `RDef`)* | `+43.1` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `52.0 ± 6.4` (`P95 63.4`) | `14/d` | `190c` |
| 125 | Vanilla | **Orc Slayer** | `orc_slayer_background.nut` | `+49.1` | **`0.27×`** *(mid ×0.85)*: `HP 63..65, Res 49..51, Fat 103..105, Ini 104..106, MAtk 60..62, RAtk 28..31, MDef 2..3, RDef -1..1` | Keep `RAtk` *(clear `RDef`)* | `+43.1` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `52.0 ± 6.4` (`P95 64.2`) | `14/d` | `190c` |
| 126 | Vanilla | **Oathtaker** | `old_paladin_background.nut` | `+50.8` | **`0.30×`** *(mid ×0.85)*: `HP 61..63, Res 46..49, Fat 92..94, Ini 114..117, MAtk 61..63, RAtk 33..36, MDef 5..7, RDef -6..-4` | Keep `RAtk` *(clear `HP`)* | `+42.5` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `51.2 ± 6.3` (`P95 62.6`) | `14/d` | `180c` |
| 127 | Vanilla | **Oathtaker** | `paladin_background.nut` | `+50.8` | **`0.30×`** *(mid ×0.85)*: `HP 61..63, Res 46..49, Fat 92..94, Ini 114..117, MAtk 61..63, RAtk 33..36, MDef 5..7, RDef -6..-4` | Keep `RAtk` *(clear `HP`)* | `+42.5` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `50.9 ± 6.2` (`P95 62.3`) | `14/d` | `180c` |
| 128 | Vanilla | **Lindwurm Slayer** | `lindwurm_slayer_background.nut` | `+51.2` | **`0.29×`** *(mid ×0.84)*: `HP 58..60, Res 43..45, Fat 98..100, Ini 112..115, MAtk 58..60, RAtk 43..46, MDef 5..7, RDef -1..0` | — | `+42.7` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `51.3 ± 6.3` (`P95 63.0`) | `14/d` | `190c` |
| 129 | Vanilla | **Hedge Knight** | `hedge_knight_background.nut` | `+52.4` | **`0.29×`** *(mid ×0.84)*: `HP 64..67, Res 39..42, Fat 104..107, Ini 93..96, MAtk 59..62, RAtk 36..38, MDef 6..8, RDef 2..3` | Keep `RAtk` *(clear `Ini`)* | `+42.9` | `0..3 (peak 1@53%)` | `79% / 17% / 4%` | **1.63★** | `51.9 ± 6.6` (`P95 64.3`) | `14/d` | `190c` |
| 130 | XBE | **Folk Hero** | `folk_hero_background.nut` | `+63.5` | **`0.20×`** *(mid ×0.7)*: `HP 65..67, Res 38..40, Fat 105..107, Ini 104..106, MAtk 61..63, RAtk 36..38, MDef 5..6, RDef 3..4` | Keep `RAtk` *(clear `Ini, RDef`)* | `+46.2` | `0(16%) / 1(67%) / 2(17%)` | `82% / 15% / 3%` | **1.22★** | `53.0 ± 5.1` (`P95 62.6`) | `14/d` | `200c` |
| 131 | XBE | **Champion** | `champion_background.nut` | `+67.8` | **`0.20×`** *(mid ×0.68)*: `HP 64..66, Res 41..43, Fat 102..104, Ini 90..92, MAtk 61..63, RAtk 36..38, MDef 7..8, RDef 5..6` | Keep `RAtk` *(clear `Ini, RDef`)* | `+45.5` | `0..3 (peak 1@63%)` | `82% / 15% / 3%` | **1.31★** | `52.4 ± 5.6` (`P95 62.8`) | `14/d` | `200c` |
| 132 | Reforged | **Renowned Swordmaster** | `rf_renowned_swordmaster_background.nut` | `+80.5` | **`0.20×`** *(mid ×0.58)*: `HP 54..56, Res 41..43, Fat 99..101, Ini 113..115, MAtk 64..66, RAtk 31..33, MDef 10..11, RDef 2..3` | Keep `RAtk` *(clear `RDef`)* | `+48.5` | `0(28%) / 1(69%) / 2(3%)` | `86% / 12% / 2%` | **0.87★** | `53.3 ± 4.6` (`P95 61.5`) | `15/d` | `220c` |
| 133 | XBE | **Paladin** | `paladin_commander_background.nut` | `+83.2` | **`0.20×`** *(mid ×0.57)*: `HP 64..66, Res 45..47, Fat 103..105, Ini 100..102, MAtk 59..61, RAtk 36..38, MDef 7..8, RDef 0..1` | Keep `RAtk` *(clear `Ini, RDef`)* | `+47.7` | `0(21%) / 1(70%) / 2(9%)` | `84% / 14% / 2%` | **1.04★** | `53.4 ± 4.9` (`P95 61.8`) | `15/d` | `210c` |

---

### 6.2 Hardened Mod Attribute Override Variants (Automatic Runtime Adaptation)

| Background | Hardened Attribute Override | Hardened `S_0` | `VarMult` | Excluded Talents | Talented Attrs `N` | Star Tiers (`1★ / 2★ / 3★`) | `E[★]` | Lvl-11 `Mean ± SD` (`P95`) | Wage | No-Gear |
| :--- | :--- | :---: | :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Bowyer** (`bowyer_background.nut`) | `HP [-5..0] (was 0), RAtk +15 (was +10)` | `+7.5` | `1.69×` | Keep `MAtk` | `0..6 (peak 4@24%)` | `38% / 23% / 39%` | **7.92★** | `41.6 ± 16.9` (`P95 67.3`) | `8/d` | `70c` |
| **Pimp** (`pimp_background.nut`) | `MAtk [0..+5] (was -5)` | `+21.5` | `1.13×` | — | `0..6 (peak 3@30%)` | `58% / 30% / 12%` | **4.77★** | `43.9 ± 14.0` (`P95 66.8`) | `10/d` | `100c` |
| **Thief** (`thief_background.nut`) | `RDef +5 (was [+5..+8])` | `+27.8` | `0.88×` | — | `0..5 (peak 3@32%)` | `65% / 27% / 8%` | **3.66★** | `45.6 ± 12.0` (`P95 65.4`) | `11/d` | `120c` |
| **Southern Assassin** (`assassin_southern_background.nut`) | `RAtk [+5..+10] (was 0)` | `+55.6` | `0.25×` | Clear `HP, Fat` | `0..3 (peak 1@56%)` | `80% / 16% / 4%` | **1.51★** | `51.9 ± 6.5` (`P95 64.1`) | `14/d` | `190c` |

---

### 6.3 Mid-Campaign Event-Conversion Backgrounds (5 Backgrounds)

| # | Background | Script | Event Mechanism & Handling |
| :-: | :--- | :--- | :--- |
| 134 | **Converted Cultist** | `converted_cultist_background.nut` | Swaps onto an existing recruit during cultist conversion events (`+2 Bravery`). Preserves existing stars & stats; daily wage reflects current `BaseProperties`. |
| 135 | **King's Guard** | `kings_guard_background.nut` | `kings_guard_1_event` spawns a special Cripple (`_addTraits = false`, scripted `2★ MAtk, 3★ MDef, 3★ RDef`), then `kings_guard_2_event` adds `+61` flat stats. Preserves scripted event reward; daily wage scales up automatically. |
| 136 | **Monk turned Flagellant** | `monk_turned_flagellant_background.nut` | Swaps onto an existing Monk in `flagellant_vs_monk_event`. Preserves existing stars & stats. |
| 137 | **Pacified Flagellant** | `pacified_flagellant_background.nut` | Swaps onto an existing Flagellant in `flagellant_vs_monk_event`. Preserves existing stars & stats. |
| 138 | **Regent in Absentia** | `regent_in_absentia_background.nut` | Swaps onto an existing Disowned Noble in `disowned_noble_welcomed_back_event` (`+10..15 Res, +6..10 Ini, +2..4 MDef, +3..5 RDef`). Preserves existing stars; daily wage scales up automatically. |
