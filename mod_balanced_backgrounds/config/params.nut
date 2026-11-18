// =========================================================================================
// Balanced Backgrounds - Tunable Mod Parameters
// =========================================================================================
// Edit the constants in this file to customize how Balanced Backgrounds scales attribute
// roll variance, talent star distributions, outlier compression, highborn pending level-ups,
// daily wages, and signing costs.
//
// After editing any value here, you can immediately preview its effect on generated recruits
// from the terminal by running:
//     ./simulate_bros.py <background> [N]
// =========================================================================================

::BalancedBackgrounds.Params <- {
	// -------------------------------------------------------------------------------------
	// 1. Target Midpoint Background & Level-11 Mean Curve
	// -------------------------------------------------------------------------------------
	// Script name (without `.nut`) of the background used as the midpoint benchmark.
	// At runtime, the mod reads this background's starting stats and anchors the star curve
	// and Level-11 target curve around its natural Level-11 power.
	TargetBackground = "militia_background",

	// Position u in (0.0, 1.0) along the star curve assigned to `TargetBackground`
	// (where `TargetMeanTalents`, `TargetStar1Pct`, and `TargetStar2Pct` apply).
	TargetAnchorU = 0.40,

	// Optional flat SSP offset added to `TargetBackground`'s natural Level-11 total.
	TargetBackgroundBonusSSP = 0.0,

	// How much expected Level-11 mean SSP changes per +1.0 starting SSP relative to
	// `TargetBackground`. With `0.17` and tight variance below, Highborn recruits are a
	// dependable "sure thing" (~45-46 SSP) while Lowborn recruits who beat them at Level 11
	// only win marginally (~+4 SSP on average, with extreme 1% outliers at ~+8 SSP).
	EndgameMeanSlope = 0.18,

	// -------------------------------------------------------------------------------------
	// 2. Starting Stat Variance Curve (Lowborn -> Highborn)
	// -------------------------------------------------------------------------------------
	// Multipliers applied to Vanilla base human roll half-widths (+/-5 on primary/secondary
	// stats, +/-2.5 on defenses). Variance interpolates from `VarianceLowbornMult` at
	// `VarianceAnchorLowSSP` down to `VarianceHighbornMult` at `VarianceAnchorHighSSP`,
	// clamping modded backgrounds beyond those anchors to [HighbornMult, LowbornMult].
	VarianceLowbornMult = 0.52,
	VarianceHighbornMult = 0.10,
	VarianceAnchorLowSSP = -8.0,
	VarianceAnchorHighSSP = 45.0,

	// Shape exponent of the lowborn-to-highborn variance transition (1.0 = strictly linear).
	VarianceCurveExponent = 1.0,

	// -------------------------------------------------------------------------------------
	// 3. Talent Star Count & Star-Tier Curve (u = 0 Highborn -> u = 1 Lowborn)
	// -------------------------------------------------------------------------------------
	// Mean number of attributes receiving stars at u = 0.0 (Highborn), u = TargetAnchorU
	// (TargetBackground), and u = 1.0 (Lowborn).
	HighbornMeanTalents = 0.50,
	TargetMeanTalents = 3.00,
	LowbornMeanTalents = 6.80,

	// Standard deviation of the discrete-Gaussian talented-attribute count distribution,
	// interpolated linearly from `StarCountSigmaHighborn` (u = 0) to `StarCountSigmaLowborn` (u = 1).
	StarCountSigmaHighborn = 0.45,
	StarCountSigmaLowborn = 0.42,

	// Star-tier percentage weights (1-star and 2-star; 3-star is `100 - Star1 - Star2`)
	// at u = 0.0 (Highborn), u = TargetAnchorU (TargetBackground), and u = 1.0 (Lowborn).
	// Lowborns rely primarily on broad 2-star growth with rare (3%) 3-star rolls so their
	// winning margin over Highborn stays tight (~+4 SSP average win, ~+8 SSP 1% outlier).
	HighbornStar1Pct = 96.0,
	HighbornStar2Pct = 4.0,
	TargetStar1Pct = 82.0,
	TargetStar2Pct = 18.0,
	LowbornStar1Pct = 5.0,
	LowbornStar2Pct = 92.0,

	// Always leave at least 1 attribute at 0 stars (required for Hardened's Discovered Talent).
	LeaveAtLeastOneUntalentedAttr = true,

	// -------------------------------------------------------------------------------------
	// 4. Outlier Midpoint Compression & Excluded Talents
	// -------------------------------------------------------------------------------------
	// Soft-compresses extreme starting stat midpoints (< LowOutlierThresholdSSP or
	// > HighOutlierThresholdSSP) while leaving middle background midpoints untouched.
	EnableOutlierCompression = true,
	LowOutlierThresholdSSP = -1.5,
	LowOutlierFloorSSP = -3.0,
	LowOutlierSlope = 0.10,
	HighOutlierThresholdSSP = 42.0,
	HighOutlierCeilingSSP = 46.5,
	HighOutlierSlope = 0.12,

	// Clear survival/funneling talent exclusions while keeping <= 1 thematic flaw.
	FilterExcludedTalents = true,

	// -------------------------------------------------------------------------------------
	// 5. Highborn Starting Pending Level-Ups (1..6 Pending Levels -> Level 2..7)
	// -------------------------------------------------------------------------------------
	// Hireable backgrounds with adjusted starting SSP >= `HighbornPendingLevelMinSSP`
	// (Executioner, Swordmaster, Squire, Beast Slayer, Assassin, Gladiator, Adventurous
	// Noble, Sellsword, Oathtaker, Hedge Knight, and equivalent modded elites) always start
	// with at least `HighbornMinPendingLevels` pending level-ups and up to `HighbornMaxPendingLevels`.
	EnableHighbornPendingLevels = true,
	HighbornPendingLevelMinSSP = 33.5,
	HighbornMinPendingLevels = 1,
	HighbornMaxPendingLevels = 6,

	// Relative probability weights for rolling 1, 2, 3, 4, 5, or 6 pending level-ups on
	// Highborn recruits (sum = 100 -> 28%, 26%, 20%, 13%, 8%, 5%; mean = 2.62 pending levels).
	PendingLevelWeight1 = 28,
	PendingLevelWeight2 = 26,
	PendingLevelWeight3 = 20,
	PendingLevelWeight4 = 13,
	PendingLevelWeight5 = 8,
	PendingLevelWeight6 = 5,

	// -------------------------------------------------------------------------------------
	// 6. Stat-Based Daily Wage & Signing Cost Formulas
	// -------------------------------------------------------------------------------------
	// DailyWage = max(MinDailyWage, round(DailyWageBase + DailyWagePerSSP * B_actor))
	MinDailyWage = 3,
	DailyWageBase = 6.8,
	DailyWagePerSSP = 0.165,

	// Equipment-free BaseHiringCost combines Level-1 stat cost with Vanilla's steep power-law
	// pending level-up surcharge `floor(PendingLevelCostMult * (Level - 1)^PendingLevelCostExp)`,
	// rounded up to the nearest 10 crowns:
	//   +1 pending lvl: +500c   | +4 pending lvls: +4,000c
	//   +2 pending lvls: +1,414c | +5 pending lvls: +5,590c
	//   +3 pending lvls: +2,598c | +6 pending lvls: +7,348c
	HiringCostBaseMult = 5.0,
	HiringCostExpSlope = 0.030,
	PendingLevelCostMult = 500.0,
	PendingLevelCostExp = 1.5,
	EquipmentHiringMarkup = 1.25,

	// -------------------------------------------------------------------------------------
	// 7. Standard Stat Point (SSP) Weights, Off-Role Discounts & Safety Floors
	// -------------------------------------------------------------------------------------
	SSPWeights = {
		Hitpoints = 1.0,
		Bravery = 1.0,
		Stamina = 1.0,
		Initiative = 0.75,
		MeleeSkill = 1.5,
		RangedSkill = 1.0,
		MeleeDefense = 1.5,
		RangedDefense = 0.75
	},

	DualOffenseDiscount = 0.40,
	SecondaryNegDiscount = 0.40,
	OffRoleAttackNegDiscount = 0.35,
	GlassArcherBodyNegDiscount = 0.65,

	MinAttributeFloor = {
		Hitpoints = 30,
		Bravery = 12,
		Stamina = 65,
		Initiative = 60,
		MeleeSkill = 25,
		RangedSkill = 15,
		MeleeDefense = -15,
		RangedDefense = -15
	}
};
