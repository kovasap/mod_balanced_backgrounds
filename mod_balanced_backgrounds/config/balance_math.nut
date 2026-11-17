// =========================================================================================
// Balanced Backgrounds - Core Mathematical Model & Calibration Tables
// =========================================================================================
// Implements the mathematical formulas documented in PLAN.md:
//   1. Standard Stat Points (SSP) evaluation for background ranges and individual recruits.
//   2. Soft midpoint outlier compression (preserving 107 of 133 background midpoints) paired
//      with a linear starting attribute variance curve (`VarMult` from 2.30x on Vanilla
//      Lowborn down to 0.20x on Vanilla Premium).
//   3. Thematic ExcludedTalents filtering (keeping at most 1 non-blocking thematic flaw).
//   4. Discrete Gaussian star-count variance + linear Level-11 mean curve calibrated so:
//        * Premium backgrounds are a low-variance, high-floor "sure thing" (~50-51.5 SSP),
//        * Weaker backgrounds have ~30% probability to surpass Premium recruits at Level 11,
//        * Top-percentile weaker backgrounds reach a substantially higher ceiling (~72-86 SSP).
//   5. Pure base-stat daily wage and equipment-free / equipped hiring cost calculations.
//
// Note: Uses only Vanilla-native ::Math methods so MSU is optional rather than required.
// =========================================================================================

::BalancedBackgrounds.Math <- {
	// Linear Level-11 mean target curve anchored around Vanilla Militia:
	//   E_11(S_adj) = MilitiaTargetEndgameSSP + MeanEndgameSlope * (S_adj - MilitiaStartSSP)
	MilitiaStartSSP = 23.30,
	MilitiaTargetEndgameSSP = 45.00,
	MeanEndgameSlope = 0.33,

	// Midpoint soft-compression thresholds & bounds (in SSP):
	LowOutlierThreshold = -8.0,
	LowOutlierFloor = -10.5,
	LowOutlierSlope = 0.10,
	HighOutlierThreshold = 42.0,
	HighOutlierCeiling = 46.5,
	HighOutlierSlope = 0.12,

	// Linear starting-stat variance multiplier curve anchored on Vanilla endpoints:
	//   S_mid = -8.0 (Beggar/Cripple) -> 2.30x base roll width
	//   S_mid = +23.3 (Militia)       -> ~1.06x base roll width
	//   S_mid = +45.0 (Hedge Knight)  -> 0.20x base roll width
	VarianceAnchorLowSSP = -8.0,
	VarianceAnchorHighSSP = 45.0,
	VarianceMultMax = 2.30,
	VarianceMultMin = 0.20,

	// Star-count Gaussian spread: sigma_N(u) = StarCountSigmaMin + StarCountSigmaSpan * u
	StarCountSigmaMin = 0.30,
	StarCountSigmaSpan = 2.50,

	// Wage and signing cost constants:
	EulerE = 2.718281828,
	MinDailyWage = 3,
	DailyWageBase = 6.8,
	DailyWagePerSSP = 0.165,
	SSPPerPreGainedLevel = 12.0,
	EquipmentHiringMarkup = 1.25,

	AttrKeys = [
		"Hitpoints",
		"Bravery",
		"Stamina",
		"Initiative",
		"MeleeSkill",
		"RangedSkill",
		"MeleeDefense",
		"RangedDefense"
	],

	// Base human Level-1 [min, max] ranges from character_background.buildAttributes().
	BaseHumanRanges = {
		Hitpoints = [ 50, 60 ],
		Bravery = [ 30, 40 ],
		Stamina = [ 90, 100 ],
		Initiative = [ 100, 110 ],
		MeleeSkill = [ 47, 57 ],
		RangedSkill = [ 32, 42 ],
		MeleeDefense = [ 0, 5 ],
		RangedDefense = [ 0, 5 ]
	},

	// Base human Level-1 attribute midpoints and half-widths prior to onChangeAttributes().
	BaseHumanMidpoint = {
		Hitpoints = 55.0,
		Bravery = 35.0,
		Stamina = 95.0,
		Initiative = 105.0,
		MeleeSkill = 52.0,
		RangedSkill = 37.0,
		MeleeDefense = 2.5,
		RangedDefense = 2.5
	},

	BaseHumanHalfWidth = {
		Hitpoints = 5.0,
		Bravery = 5.0,
		Stamina = 5.0,
		Initiative = 5.0,
		MeleeSkill = 5.0,
		RangedSkill = 5.0,
		MeleeDefense = 2.5,
		RangedDefense = 2.5
	},

	// Safety minimum floors so wide lowborn variance never rolls broken/unplayable base stats.
	MinAttributeFloor = {
		Hitpoints = 30,
		Bravery = 12,
		Stamina = 65,
		Initiative = 60,
		MeleeSkill = 25,
		RangedSkill = 15,
		MeleeDefense = -15,
		RangedDefense = -15
	},

	// SSP value per point of each attribute, inversely proportional to 0-star level-up rolls.
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

	// Exact analytical expected top-3 star gain G_top3(u) at u = 0.00, 0.01, ..., 1.00
	// under the discrete-Gaussian star-count variance curve for each open talent pool class:
	//   none : all 8 attributes open
	//   w100 : 1 attribute with 1.00 SSP weight excluded (RangedSkill, Bravery, Hitpoints, or Fatigue)
	//   w150 : 1 attribute with 1.50 SSP weight excluded (MeleeSkill or MeleeDefense)
	//   w075 : 1 attribute with 0.75 SSP weight excluded (Initiative or RangedDefense)
	GTop3Table = {
		none = [
			0.11, 0.41, 0.94, 1.64, 2.38, 3.06, 3.73, 4.13, 4.62, 5.03,
			5.52, 5.93, 6.49, 6.94, 7.45, 8.04, 8.63, 9.18, 9.57, 10.20,
			10.85, 11.35, 12.02, 12.44, 13.15, 13.64, 14.23, 14.88, 15.32, 15.86,
			16.35, 17.11, 17.49, 17.91, 18.35, 19.10, 19.53, 20.38, 20.48, 21.18,
			21.66, 22.19, 22.68, 23.26, 23.74, 24.18, 24.75, 25.58, 26.12, 26.38,
			26.78, 27.49, 28.21, 28.74, 29.27, 29.49, 30.07, 30.50, 31.12, 31.98,
			32.43, 32.52, 33.11, 33.64, 34.16, 34.54, 35.11, 35.36, 35.83, 36.14,
			36.74, 37.64, 38.00, 38.03, 38.37, 39.00, 39.29, 39.87, 40.16, 40.38,
			40.80, 41.08, 41.40, 41.87, 42.13, 42.21, 42.56, 42.98, 43.45, 43.74,
			43.98, 44.37, 44.45, 44.68, 44.91, 45.40, 45.63, 45.63, 45.87, 46.22,
			46.42
		],
		w100 = [
			0.12, 0.41, 0.95, 1.65, 2.40, 3.09, 3.76, 4.16, 4.66, 5.08,
			5.56, 5.98, 6.55, 7.00, 7.52, 8.10, 8.71, 9.25, 9.65, 10.29,
			10.95, 11.45, 12.12, 12.55, 13.27, 13.76, 14.36, 15.01, 15.46, 16.01,
			16.50, 17.27, 17.65, 18.08, 18.53, 19.29, 19.72, 20.58, 20.68, 21.40,
			21.88, 22.42, 22.92, 23.15, 23.91, 24.48, 24.89, 25.56, 26.22, 26.32,
			26.82, 27.51, 28.04, 28.45, 29.08, 29.56, 29.89, 30.44, 30.86, 31.44,
			31.89, 32.08, 32.48, 33.31, 33.70, 34.23, 34.62, 34.87, 35.26, 35.58,
			35.97, 36.69, 37.11, 37.11, 37.42, 38.04, 38.34, 38.67, 38.97, 39.19,
			39.48, 40.01, 40.40, 40.85, 41.16, 41.16, 41.43, 41.87, 42.14, 42.47,
			42.73, 43.27, 43.27, 43.52, 43.76, 44.17, 44.40, 44.40, 44.64, 45.02,
			45.25
		],
		w150 = [
			0.11, 0.38, 0.89, 1.54, 2.24, 2.88, 3.51, 3.89, 4.35, 4.74,
			5.19, 5.58, 6.11, 6.53, 7.02, 7.56, 8.12, 8.64, 9.01, 9.60,
			10.21, 10.68, 11.31, 11.71, 12.38, 12.83, 13.39, 13.99, 14.41, 14.92,
			15.37, 16.08, 16.44, 16.83, 17.25, 17.94, 18.35, 19.14, 19.23, 19.89,
			20.34, 20.83, 21.29, 21.51, 22.21, 22.74, 23.12, 23.74, 24.36, 24.45,
			24.91, 25.55, 26.04, 26.42, 27.01, 27.44, 27.75, 28.26, 28.65, 29.19,
			29.60, 29.78, 30.14, 30.91, 31.28, 31.76, 32.12, 32.34, 32.70, 33.00,
			33.35, 34.01, 34.40, 34.40, 34.68, 35.24, 35.51, 35.81, 36.07, 36.27,
			36.53, 37.01, 37.36, 37.76, 38.03, 38.03, 38.28, 38.67, 38.90, 39.18,
			39.41, 39.88, 39.88, 40.09, 40.30, 40.65, 40.85, 40.85, 41.05, 41.38,
			41.57
		],
		w075 = [
			0.12, 0.42, 0.98, 1.71, 2.48, 3.19, 3.88, 4.30, 4.82, 5.25,
			5.75, 6.18, 6.77, 7.23, 7.77, 8.37, 9.00, 9.56, 9.97, 10.63,
			11.31, 11.83, 12.52, 12.96, 13.70, 14.21, 14.83, 15.50, 15.96, 16.52,
			17.03, 17.82, 18.21, 18.65, 19.11, 19.88, 20.33, 21.21, 21.31, 22.04,
			22.54, 23.09, 23.60, 23.84, 24.62, 25.21, 25.63, 26.32, 27.00, 27.10,
			27.61, 28.32, 28.87, 29.29, 29.94, 30.42, 30.77, 31.33, 31.76, 32.36,
			32.81, 33.01, 33.42, 34.26, 34.67, 35.20, 35.60, 35.85, 36.25, 36.57,
			36.97, 37.70, 38.12, 38.12, 38.43, 39.05, 39.36, 39.68, 39.98, 40.20,
			40.49, 41.02, 41.40, 41.85, 42.15, 42.15, 42.42, 42.85, 43.11, 43.42,
			43.67, 44.19, 44.19, 44.43, 44.67, 45.06, 45.28, 45.28, 45.50, 45.87,
			46.08
		]
	},

	// Symmetric round-half-away-from-zero helper to avoid C++ negative rounding ambiguity.
	function roundInt( _x )
	{
		return _x >= 0.0 ? ::Math.floor(_x + 0.5).tointeger() : (-::Math.floor(-_x + 0.5)).tointeger();
	},

	// Clamp an integer _v into [_lo, _hi] using Vanilla-native ::Math.min / ::Math.max.
	function clampInt( _v, _lo, _hi )
	{
		return ::Math.max(_lo, ::Math.min(_hi, _v));
	},

	// Clamp a float _v into [_lo, _hi] using Vanilla-native ::Math.minf / ::Math.maxf.
	function clampFloat( _v, _lo, _hi )
	{
		return ::Math.maxf(_lo, ::Math.minf(_hi, _v));
	},

	// Filter a background's ExcludedTalents list so survival/funneling lockouts are cleared
	// while preserving at most 1 thematic flaw (e.g. RangedSkill on knights, Bravery on Deserter).
	function filterExcludedTalents( _bgID, _excluded )
	{
		if (_excluded == null || _excluded.len() == 0)
		{
			return [];
		}

		if (_bgID == "background.deserter" && _excluded.find(::Const.Attributes.Bravery) != null)
		{
			return [ ::Const.Attributes.Bravery ];
		}

		if (_bgID == "background.cripple" && _excluded.find(::Const.Attributes.Initiative) != null)
		{
			return [ ::Const.Attributes.Initiative ];
		}

		if (_bgID == "background.hackflows_leper" && _excluded.find(::Const.Attributes.Hitpoints) != null)
		{
			return [ ::Const.Attributes.Hitpoints ];
		}

		foreach (attr in _excluded)
		{
			if (attr == ::Const.Attributes.RangedSkill || attr == ::Const.Attributes.MeleeSkill)
			{
				return [ attr ];
			}
		}

		return [];
	},

	// Compute the Standard Stat Point (SSP) value of an 8-attribute delta table relative to
	// the Base Human Level-1 midpoint, applying off-role negative and dual-offense discounts.
	function computeSSPFromDeltas( _d )
	{
		local isDedicatedRanged = _d.RangedSkill >= 10.0 && _d.MeleeSkill <= 0.0;
		local isGlassArcher = _d.RangedSkill >= 20.0 && _d.MeleeSkill < 0.0;
		local totalSSP = 0.0;

		foreach (k in this.AttrKeys)
		{
			local val = _d[k];
			local w = this.SSPWeights[k];

			if (val < 0.0)
			{
				if (k == "Initiative" || k == "RangedDefense")
				{
					val *= 0.40;
				}
				else if (k == "RangedSkill" && _d.MeleeSkill >= 5.0)
				{
					val *= 0.35;
				}
				else if ((k == "MeleeSkill" || k == "MeleeDefense") && isDedicatedRanged)
				{
					val *= 0.35;
				}
				else if ((k == "Hitpoints" || k == "Stamina") && isGlassArcher)
				{
					val *= 0.65;
				}
			}

			totalSSP += val * w;
		}

		// Non-hybrid builds invest primarily in one offensive skill; discount the smaller positive attack skill.
		local posMeleeSSP = ::Math.maxf(0.0, _d.MeleeSkill * this.SSPWeights.MeleeSkill);
		local posRangedSSP = ::Math.maxf(0.0, _d.RangedSkill * this.SSPWeights.RangedSkill);

		if (posMeleeSSP > 0.0 && posRangedSSP > 0.0)
		{
			totalSSP -= 0.40 * ::Math.minf(posMeleeSSP, posRangedSSP);
		}

		return totalSSP;
	},

	// Evaluate the expected starting SSP of an onChangeAttributes() [minDelta, maxDelta] table.
	function computeSSPFromAttrRanges( _attrs )
	{
		local midpoints = {};

		foreach (k in this.AttrKeys)
		{
			local range = _attrs[k];
			midpoints[k] <- (range[0] + range[1]) * 0.5;
		}

		return this.computeSSPFromDeltas(midpoints);
	},

	// Helper: return a copy of _attrs with either positive or negative entries scaled by _alpha.
	function scaleSignedAttrRanges( _attrs, _alpha, _scalePositive )
	{
		local scaled = {};

		foreach (k in this.AttrKeys)
		{
			local v = _attrs[k];

			if (_scalePositive)
			{
				scaled[k] <- [
					v[0] > 0 ? this.roundInt(v[0] * _alpha) : v[0],
					v[1] > 0 ? this.roundInt(v[1] * _alpha) : v[1]
				];
			}
			else
			{
				scaled[k] <- [
					v[0] < 0 ? this.roundInt(v[0] * _alpha) : v[0],
					v[1] < 0 ? this.roundInt(v[1] * _alpha) : v[1]
				];
			}
		}

		return scaled;
	},

	// Linear starting-attribute variance multiplier anchored on Vanilla Lowborn (-8 SSP -> 2.30x)
	// through Vanilla Premium (+45 SSP -> 0.20x), clamped cleanly for modded outliers.
	function computeVarianceMult( _sMid )
	{
		local t = this.clampFloat((_sMid - this.VarianceAnchorLowSSP) / (this.VarianceAnchorHighSSP - this.VarianceAnchorLowSSP), 0.0, 1.0);
		return this.VarianceMultMax + t * (this.VarianceMultMin - this.VarianceMultMax);
	},

	// Transform a background's raw `onChangeAttributes()` table by:
	//   1. Soft-compressing only extreme low (< -8.0 SSP) or high (> +42.0 SSP) midpoints.
	//   2. Applying the linear starting attribute roll width `computeVarianceMult(sMid)` around
	//      each attribute's midpoint so lowborns have wide prodigy/dud variance while premium
	//      highborns roll tight, dependable stats (automatically synced to Reforged's tooltip).
	function transformAttributeRanges( _rawAttrs )
	{
		if (_rawAttrs == null)
		{
			return _rawAttrs;
		}

		// Step 1: Soft-compress extreme midpoint outliers while keeping 107/133 midpoints intact.
		local s0 = this.computeSSPFromAttrRanges(_rawAttrs);
		local compAttrs = _rawAttrs;

		if (s0 < this.LowOutlierThreshold || s0 > this.HighOutlierThreshold)
		{
			local scalePositive = s0 > this.HighOutlierThreshold;
			local sTarget = scalePositive
				? ::Math.minf(this.HighOutlierCeiling, this.HighOutlierThreshold + this.HighOutlierSlope * (s0 - this.HighOutlierThreshold))
				: ::Math.maxf(this.LowOutlierFloor, this.LowOutlierThreshold + this.LowOutlierSlope * (s0 - this.LowOutlierThreshold));

			local bestErr = 999999.0;

			for (local step = 10; step <= 100; ++step)
			{
				local cand = this.scaleSignedAttrRanges(_rawAttrs, step * 0.01, scalePositive);
				local err = ::Math.abs(this.computeSSPFromAttrRanges(cand) - sTarget);

				if (err < bestErr)
				{
					bestErr = err;
					compAttrs = cand;
				}
			}
		}

		// Step 2: Apply linear variance width around each attribute's expected midpoint.
		local sMid = this.computeSSPFromAttrRanges(compAttrs);
		local varMult = this.computeVarianceMult(sMid);
		local out = {};

		foreach (k in this.AttrKeys)
		{
			local midDelta = (compAttrs[k][0] + compAttrs[k][1]) * 0.5;
			local baseRange = this.BaseHumanRanges[k];
			local baseHalf = this.BaseHumanHalfWidth[k];
			local targetHalf = baseHalf * varMult;

			// Preserve Reforged's Old Swordmaster scenario check (`MeleeSkill[0] < 8`) on
			// backgrounds whose original MeleeSkill minimum delta was below +8.
			if (k == "MeleeSkill" && _rawAttrs.MeleeSkill[0] < 8 && this.roundInt(midDelta - targetHalf + baseHalf) >= 8)
			{
				targetHalf = ::Math.maxf(targetHalf, midDelta - 2.0);
			}

			local c0 = this.roundInt(midDelta - targetHalf + baseHalf);
			local c1 = this.roundInt(midDelta + targetHalf - baseHalf);

			local floorVal = this.MinAttributeFloor[k];

			if (baseRange[0] + c0 < floorVal)
			{
				c0 = floorVal - baseRange[0];
			}

			if (baseRange[0] + c0 > baseRange[1] + c1)
			{
				local fixedVal = ::Math.max(floorVal, this.roundInt(this.BaseHumanMidpoint[k] + midDelta));
				c0 = fixedVal - baseRange[0];
				c1 = fixedVal - baseRange[1];
			}

			out[k] <- [ c0, c1 ];
		}

		return out;
	},

	// Compute the linear Level-11 mean target SSP for a background with starting budget _sAdj.
	// Premium backgrounds target a higher mean (~50.5 SSP, tight SD) as a "sure thing", while
	// Lowborns target a lower mean (~38-41 SSP, wide SD) yielding a ~30% upset rate vs Premium
	// and a much higher 95th/99th-percentile ceiling.
	function computeTargetEndgameSSP( _sAdj )
	{
		return this.MilitiaTargetEndgameSSP + this.MeanEndgameSlope * (_sAdj - this.MilitiaStartSSP);
	},

	// Map an ExcludedTalents array to its corresponding GTop3Table pool key.
	function getPoolKey( _excluded )
	{
		if (_excluded == null || _excluded.len() == 0)
		{
			return "none";
		}

		local ex = _excluded[0];

		if (ex == ::Const.Attributes.MeleeSkill || ex == ::Const.Attributes.MeleeDefense)
		{
			return "w150";
		}

		if (ex == ::Const.Attributes.Initiative || ex == ::Const.Attributes.RangedDefense)
		{
			return "w075";
		}

		return "w100";
	},

	// Convert continuous star-curve position _u in [0.0, 1.0] and slot cap _maxN into:
	//   CountWeights : discrete-Gaussian [attributeCount, percentWeight] summing to 100, whose
	//                  standard deviation grows linearly with _u (tight on Premium, wide on Lowborn)
	//   TierWeights  : [weight1Star, weight2Star, weight3Star] summing to 100
	function paramsFromU( _u, _maxN )
	{
		local u = this.clampFloat(_u, 0.0, 1.0);
		local muN = 3.0;
		local p1 = 60.0;
		local p2 = 30.0;

		if (u <= 0.40)
		{
			// Highborn / Elite segment (u = 0.00 -> Militia anchor at u = 0.40)
			local t = u / 0.40;
			muN = 0.15 + t * (3.00 - 0.15);
			p1 = 92.0 + t * (60.0 - 92.0);
			p2 = 8.0 + t * (30.0 - 8.0);
		}
		else
		{
			// Lowborn / High-Variance segment (Militia anchor at u = 0.40 -> u = 1.00)
			local t = (u - 0.40) / 0.60;
			muN = 3.00 + t * (6.20 - 3.00);
			p1 = 60.0 + t * (10.0 - 60.0);
			p2 = 30.0 + t * (15.0 - 30.0);
		}

		// Linearly widen star-count spread sigma_N from 0.30 (Premium) to 2.80 (Lowborn).
		local sigmaN = this.StarCountSigmaMin + this.StarCountSigmaSpan * u;
		local rawWeights = array(_maxN + 1, 0.0);
		local rawSum = 0.0;

		for (local c = 0; c <= _maxN; ++c)
		{
			local z = (c - muN) / sigmaN;
			local w = ::Math.pow(this.EulerE, -0.5 * z * z);
			rawWeights[c] = w;
			rawSum += w;
		}

		local countWeights = [];
		local totalPct = 0;

		for (local c = 0; c <= _maxN; ++c)
		{
			local pct = rawSum > 0.0 ? this.roundInt(100.0 * rawWeights[c] / rawSum) : 0;

			if (pct > 0)
			{
				countWeights.push([ c, pct ]);
				totalPct += pct;
			}
		}

		if (countWeights.len() == 0)
		{
			countWeights.push([ 0, 100 ]);
			totalPct = 100;
		}

		local roundingDiff = 100 - totalPct;

		if (roundingDiff != 0)
		{
			local bestIdx = 0;

			for (local idx = 1; idx < countWeights.len(); ++idx)
			{
				if (countWeights[idx][1] > countWeights[bestIdx][1])
				{
					bestIdx = idx;
				}
			}

			countWeights[bestIdx][1] += roundingDiff;
		}

		local tw1 = this.roundInt(p1);
		local tw2 = this.roundInt(p2);
		local tw3 = ::Math.max(0, 100 - tw1 - tw2);

		return {
			CountWeights = countWeights,
			TierWeights = [ tw1, tw2, tw3 ]
		};
	},

	// Solve the star probability profile (CountWeights, TierWeights, OpenAttrs) for _bg
	// so S_adj + G_top3(u) matches the linear Level-11 mean target E_11(S_adj).
	function getStarProfileForBackground( _bg )
	{
		local attrs = _bg != null ? _bg.onChangeAttributes() : null;
		local sAdj = attrs != null ? this.computeSSPFromAttrRanges(attrs) : this.MilitiaStartSSP;
		local excluded = _bg != null ? _bg.getExcludedTalents() : [];

		local openAttrs = [];

		for (local i = 0; i < ::Const.Attributes.COUNT; ++i)
		{
			if (excluded.find(i) == null)
			{
				openAttrs.push(i);
			}
		}

		// Cap talented slots at openAttrs.len() - 1 so every recruit has at least one 0-star
		// attribute (required by Hardened's Discovered Talent perk).
		local maxN = ::Math.max(0, openAttrs.len() - 1);
		local poolKey = this.getPoolKey(excluded);
		local table = this.GTop3Table[poolKey];
		local desiredGain = this.computeTargetEndgameSSP(sAdj) - sAdj;

		local bestStep = 40;
		local bestErr = 999999.0;

		for (local step = 0; step <= 100; ++step)
		{
			local err = ::Math.abs(table[step] - desiredGain);

			if (err < bestErr)
			{
				bestErr = err;
				bestStep = step;
			}
		}

		local profile = this.paramsFromU(bestStep * 0.01, maxN);
		profile.OpenAttrs <- openAttrs;
		return profile;
	},

	// Roll an array of 8 talent star values (0..3) for _actor based on its background's profile.
	function rollTalentsForActor( _actor )
	{
		local talents = array(::Const.Attributes.COUNT, 0);
		local bg = _actor.getBackground();

		if (bg != null && bg.isUntalented())
		{
			return talents;
		}

		local profile = this.getStarProfileForBackground(bg);
		local openPool = clone profile.OpenAttrs;

		if (openPool.len() == 0)
		{
			return talents;
		}

		// Step 1: Roll how many attributes receive talent stars.
		local rCount = ::Math.rand(1, 100);
		local cumulative = 0;
		local chosenN = profile.CountWeights[profile.CountWeights.len() - 1][0];

		foreach (pair in profile.CountWeights)
		{
			cumulative += pair[1];

			if (rCount <= cumulative)
			{
				chosenN = pair[0];
				break;
			}
		}

		chosenN = this.clampInt(chosenN, 0, ::Math.max(0, openPool.len() - 1));

		// Step 2: Uniformly sample chosenN distinct open attributes and roll 1, 2, or 3 stars on each.
		local tw1 = profile.TierWeights[0];
		local tw12 = tw1 + profile.TierWeights[1];

		for (local d = 0; d < chosenN && openPool.len() > 0; ++d)
		{
			local pickIdx = ::Math.rand(0, openPool.len() - 1);
			local attrIdx = openPool[pickIdx];
			openPool.remove(pickIdx);

			local rStar = ::Math.rand(1, 100);

			if (rStar <= tw1)
			{
				talents[attrIdx] = 1;
			}
			else if (rStar <= tw12)
			{
				talents[attrIdx] = 2;
			}
			else
			{
				talents[attrIdx] = 3;
			}
		}

		return talents;
	},

	// Compute an individual character's BaseProperties SSP relative to the Base Human midpoint.
	// Subtracts Hardened's flat +5 HP global offset when present so wages/costs stay neutral.
	function computeActorBaseSSP( _actor )
	{
		local b = _actor.getBaseProperties();
		local bg = _actor.getBackground();
		local hpOffset = (bg != null && ("HD_HitpointModifier" in bg.m)) ? bg.m.HD_HitpointModifier : 0;

		local deltas = {
			Hitpoints = (b.Hitpoints - hpOffset) - this.BaseHumanMidpoint.Hitpoints,
			Bravery = b.Bravery - this.BaseHumanMidpoint.Bravery,
			Stamina = b.Stamina - this.BaseHumanMidpoint.Stamina,
			Initiative = b.Initiative - this.BaseHumanMidpoint.Initiative,
			MeleeSkill = b.MeleeSkill - this.BaseHumanMidpoint.MeleeSkill,
			RangedSkill = b.RangedSkill - this.BaseHumanMidpoint.RangedSkill,
			MeleeDefense = b.MeleeDefense - this.BaseHumanMidpoint.MeleeDefense,
			RangedDefense = b.RangedDefense - this.BaseHumanMidpoint.RangedDefense
		};

		return this.computeSSPFromDeltas(deltas);
	},

	// Compute daily wage (crowns/day) purely from current BaseProperties.
	// Because BaseProperties increases on every level-up and permanent event stat gain, wages
	// grow naturally across a brother's career (~5-14/day at Lvl 1 -> ~28-32/day at Lvl 11).
	function calcStatDailyWage( _actor )
	{
		local bActor = this.computeActorBaseSSP(_actor);
		return ::Math.max(this.MinDailyWage, this.roundInt(this.DailyWageBase + this.DailyWagePerSSP * bActor));
	},

	// Compute equipment-free signing cost (crowns) purely from BaseProperties and starting level.
	// Talent stars are intentionally unpriced so high-ceiling lowborns remain cheap to prospect.
	function calcBaseHiringCost( _actor )
	{
		local bActor = this.computeActorBaseSSP(_actor);
		local level = ::Math.max(1, _actor.getLevel());
		local bHire = bActor + this.SSPPerPreGainedLevel * (level - 1);
		local scaled = ::Math.ceil(5.0 * ::Math.pow(this.EulerE, 0.030 * bHire)).tointeger();
		return 10 * ::Math.max(2, scaled);
	},

	// Compute equipped signing cost (crowns): BaseHiringCost + 1.25x item value, rounded up to 10c.
	function calcEquippedHiringCost( _actor, _baseHiringCost )
	{
		local items = _actor.getItems().getAllItems();
		local equipCost = 0.0;

		foreach (item in items)
		{
			equipCost += item.getValue();
		}

		equipCost *= this.EquipmentHiringMarkup;
		return 10 * ::Math.ceil((_baseHiringCost + equipCost) * 0.1).tointeger();
	}
};
