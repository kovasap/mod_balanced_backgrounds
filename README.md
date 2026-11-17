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

At runtime, the mod evaluates every background's starting attribute modifiers in Standard Stat Points (SSP), clears artificial talent lockouts down to at most one thematic flaw, and applies a linear variance curve across both starting stat roll ranges and talent star counts. Premium backgrounds roll tight, dependable starting stats with few stars—making them a consistent "sure thing" with a slightly higher average Level-11 total—while weaker lowborn backgrounds roll wider stat ranges and heavier, higher-variance star distributions, giving them roughly a 30% chance to surpass a premium recruit at Level 11 and a substantially higher ceiling when you find a prodigy. Starting Origin roster characters (including Companions) are also adjusted to use these same background-calibrated star rules.

In addition, character daily wages, tryout fees, and base signing costs are calculated purely from each recruit's actual `BaseProperties` stats rather than preset background multipliers, so wages scale naturally as a brother levels up and gains stats. In the Town Hire Screen, an **"Include Equipment"** checkbox lets you toggle between hiring recruits with their starting gear or hiring them unequipped for their base stat signing cost alone. All calculations run dynamically without custom save-file serialization, supporting Vanilla Battle Brothers as well as overhaul and background mods such as Reforged, Hardened, and More Backgrounds and Events (XBE).

## Notes

This mod should work with other mods that add more backgrounds, specifically
https://github.com/Suor/battle-brothers-xbe.

See background stats at https://docs.google.com/spreadsheets/d/14WmAFNdYft-YVDjEW_BHQHFPfnuBhmMs-SKR6tIQ2Ws/edit?gid=1944605384#gid=1944605384
