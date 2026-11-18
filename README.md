# Balanced Backgrounds

All the bros you hire are humans - what they did in the past shouldn't give them
a permanent ceiling for their power level as they gain experience with your
company!

This mod redistributes talent stars among backgrounds so that backgrounds with a
small total amount of starting stats get more stars, and bros with more starting
stats get less.
Ultimately all bros should be of similar power level at endgame, but bros from
better backgrounds will start off with better stats.

This mod also makes daily wage and hiring cost a function of base stats alone,
not background.

Finally, this mod gives you the option to hire bros without their equipment if
you do not want to pay for it.
Thematically the bro will sell the equipment themselves and keep the money
before joining the company.

Note that you can still get bros with high or low stats as per their background
attribute ranges, distribution of stars is still random, and the number of stars
granted still also has some variance.
The goal is to make it so that you can reliably carry a good lowborn to endgame,
not so that there are no bad bros anymore.

The average endgame power level of all backgrounds with this mod is around that
of a militia background.

## How It Works

At runtime, the mod evaluates every background's starting attribute modifiers in Standard Stat Points (SSP), clears artificial talent lockouts down to at most one thematic flaw, and applies a linear variance curve across both starting stat roll ranges and talent star counts. Premium highborn backgrounds roll tight, dependable starting stats with few stars and always start with 1 to 6 pending level-ups—making them an immediate, reliable "sure thing" with a higher average Level-11 total—while weaker lowborn backgrounds roll wider stat ranges and broad, mostly 2-star talent distributions that let a standout lowborn surpass a highborn recruit at Level 11 by a tight margin (~4 SSP, or ~8 SSP for 1% prodigies). Starting Origin roster characters (including Companions) are also adjusted to use these same background-calibrated star rules.

In addition, character daily wages, tryout fees, and signing costs are calculated dynamically from each recruit's actual `BaseProperties` stats plus Vanilla's power-law surcharge for pre-gained pending level-ups, making veteran highborn recruits appropriately expensive upfront while keeping daily wages tied purely to realized stats. In the Town Hire Screen, an **"Include Equipment"** checkbox lets you toggle between hiring recruits with their starting gear or hiring them unequipped for their character signing cost alone. All calculations run dynamically without custom save-file serialization, supporting Vanilla Battle Brothers as well as overhaul and background mods such as Reforged, Hardened, and More Backgrounds and Events (XBE).

## Simulating Recruits & Tuning Parameters (`simulate_bros.py`)

[`simulate_bros.py`](simulate_bros.py) is a standalone Python 3 CLI tool that generates $N$ random recruits of a specified background side-by-side in **Vanilla** and **Balanced Backgrounds**, reading tunable constants directly from [`mod_balanced_backgrounds/config/params.nut`](mod_balanced_backgrounds/config/params.nut).

> **Prerequisite:** Clone [`Battle-Brothers-Scripts`](https://github.com/ninkjin/Battle-Brothers-Scripts) into the repository root so the script can read Vanilla background definitions (and optionally [`mod-reforged`](https://github.com/Battle-Modders/mod-reforged) or [`battle-brothers-xbe`](https://github.com/Suor/battle-brothers-xbe) to simulate their custom backgrounds as well).

### Basic Usage

```bash
# Generate 8 random recruits of a background (default N = 8)
./simulate_bros.py beggar
./simulate_bros.py militia 10
./simulate_bros.py hedge_knight 8 --seed 42

# List all discovered Vanilla / Reforged / XBE backgrounds and their calibrated curves
./simulate_bros.py --list
```

Each recruit row prints:
- **`Start`**: Starting character level and pending level-ups (e.g. `L1(+0)` or `L4(+3)`).
- **8 Attribute Columns (`HP`, `Fat`, `Res`, `Ini`, `MAtk`, `MDef`, `RAtk`, `RDef`)**: Formatted as `L1Base + Stars -> Lvl11`, showing the rolled Level-1 stat, rolled talent stars (`*` to `***`), and projected Level-11 value if that attribute is leveled on all 10 level-ups.
- **`Stars` / `L1 SSP` / `L11 SSP`**: Total talent stars, starting Standard Stat Points, and expected Level-11 build SSP.
- **`NoGear` / `Wage`**: Equipment-free signing cost (including any pending level-up surcharge) and `Level 1 -> Level 11` daily wage.
- **Monte Carlo Summary**: Distribution percentiles (`Mean`, `SD`, `P10`–`P99`), Level-11 win rate against a benchmark background (`--compare`), average winning margin, and `1%` (`P99`) outlier delta.

### Iterating on Mod Parameters

You can either edit [`mod_balanced_backgrounds/config/params.nut`](mod_balanced_backgrounds/config/params.nut) directly and re-run `./simulate_bros.py`, or test temporary overrides from the command line with `-p` / `--set KEY=VALUE`:

```bash
# Preview wider lowborn roll variance and a flatter Level-11 slope without editing files
./simulate_bros.py daytaler 6 --seed 42 \
  -p VarianceLowbornMult=0.75 \
  -p EndgameMeanSlope=0.12

# Compare Beggar directly against Adventurous Noble with 10,000 Monte Carlo trials
./simulate_bros.py beggar 6 --compare adventurous_noble --trials 10000
```

## Notes

This mod should work with other mods that add more backgrounds, specifically
https://github.com/Suor/battle-brothers-xbe.

See background stats at https://docs.google.com/spreadsheets/d/14WmAFNdYft-YVDjEW_BHQHFPfnuBhmMs-SKR6tIQ2Ws/edit?gid=1944605384#gid=1944605384
