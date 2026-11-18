// =========================================================================================
// Balanced Backgrounds - Core Mathematical Model & Dynamic Calibration Solver
// =========================================================================================
// Evaluates background and character attributes using the tunable constants defined in
// `mod_balanced_backgrounds/config/params.nut`:
//   1. Evaluates Standard Stat Points (SSP) for background ranges and individual recruits.
//   2. Soft-compresses extreme midpoint outliers and applies the lowborn-to-highborn
//      starting attribute roll variance curve (`computeVarianceMult`).
//   3. Dynamically resolves `Params.TargetBackground` (e.g. `"militia_background"`) at
//      runtime to anchor both starting SSP and expected Level-11 endgame SSP.
//   4. Dynamically computes exact expected top-3 star gain curves `G_top3(u)` for any
//      open attribute pool via single-pass dynamic programming (zero hardcoded tables, so
//      any parameter edit in `params.nut` takes effect automatically).
//   5. Computes pure BaseProperties-driven daily wages and equipment-free / equipped costs.
//
// Note: Uses only Vanilla-native ::Math methods so MSU is optional rather than required.
// =========================================================================================

::BalancedBackgrounds.Math <- {
	EulerE = 2.718281828,
	CurveSteps = 51,

	// Runtime caches populated lazily from `::BalancedBackgrounds.Params`; call
	// `invalidateCache()` if modifying `::BalancedBackgrounds.Params` at runtime.
	PoolCurveCache = {},
	TargetAnchorCache = null,

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

	// Mapping from ::Const.Attributes enum indices (0..7) to `AttrKeys` names.
	// Note: ::Const.Attributes.Fatigue (index 2) corresponds to property key `"Stamina"`.
	EnumToAttrKey = [
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

	// Clear cached G_top3 curves and target-background anchors after live parameter changes.
	function invalidateCache()
	{
		this.PoolCurveCache = {};
		this.TargetAnchorCache = null;
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

	// Compute binomial coefficient C(_n, _k) for small integers (0 <= _k <= _n <= 8).
	function binomial( _n, _k )
	{
		if (_k < 0 || _k > _n)
		{
			return 0;
		}

		if (_k == 0 || _k == _n)
		{
			return 1;
		}

		local k = ::Math.min(_k, _n - _k);
		local res = 1;

		for (local i = 1; i <= k; ++i)
		{
			res = (res * (_n - k + i)) / i;
		}

		return res;
	},

	// Filter a background's ExcludedTalents list down to <= 1 non-blocking thematic flaw
	// (unless `Params.FilterExcludedTalents` is disabled).
	function filterExcludedTalents( _bgID, _excluded )
	{
		if (_excluded == null || _excluded.len() == 0)
		{
			return [];
		}

		if (!::BalancedBackgrounds.Params.FilterExcludedTalents)
		{
			return clone _excluded;
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
	// the Base Human Level-1 midpoint using weights and discounts from `Params`.
	function computeSSPFromDeltas( _d )
	{
		local p = ::BalancedBackgrounds.Params;
		local weights = p.SSPWeights;
		local isDedicatedRanged = _d.RangedSkill >= 10.0 && _d.MeleeSkill <= 0.0;
		local isGlassArcher = _d.RangedSkill >= 20.0 && _d.MeleeSkill < 0.0;
		local totalSSP = 0.0;

		foreach (k in this.AttrKeys)
		{
			local val = _d[k];
			local w = weights[k];

			if (val < 0.0)
			{
				if (k == "Initiative" || k == "RangedDefense")
				{
					val *= p.SecondaryNegDiscount;
				}
				else if (k == "RangedSkill" && _d.MeleeSkill >= 5.0)
				{
					val *= p.OffRoleAttackNegDiscount;
				}
				else if ((k == "MeleeSkill" || k == "MeleeDefense") && isDedicatedRanged)
				{
					val *= p.OffRoleAttackNegDiscount;
				}
				else if ((k == "Hitpoints" || k == "Stamina") && isGlassArcher)
				{
					val *= p.GlassArcherBodyNegDiscount;
				}
			}

			totalSSP += val * w;
		}

		local posMeleeSSP = ::Math.maxf(0.0, _d.MeleeSkill * weights.MeleeSkill);
		local posRangedSSP = ::Math.maxf(0.0, _d.RangedSkill * weights.RangedSkill);

		if (posMeleeSSP > 0.0 && posRangedSSP > 0.0)
		{
			totalSSP -= p.DualOffenseDiscount * ::Math.minf(posMeleeSSP, posRangedSSP);
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

	// Compute the starting-attribute roll width multiplier for midpoint SSP `_sMid`,
	// interpolating from `VarianceLowbornMult` at `VarianceAnchorLowSSP` down to
	// `VarianceHighbornMult` at `VarianceAnchorHighSSP` with shape `VarianceCurveExponent`.
	function computeVarianceMult( _sMid )
	{
		local p = ::BalancedBackgrounds.Params;
		local span = p.VarianceAnchorHighSSP - p.VarianceAnchorLowSSP;
		local t = span > 0.0 ? this.clampFloat((_sMid - p.VarianceAnchorLowSSP) / span, 0.0, 1.0) : 0.5;

		if (p.VarianceCurveExponent != 1.0 && t > 0.0 && t < 1.0)
		{
			t = ::Math.pow(t, p.VarianceCurveExponent);
		}

		return p.VarianceLowbornMult + t * (p.VarianceHighbornMult - p.VarianceLowbornMult);
	},

	// Transform a background's raw `onChangeAttributes()` table by:
	//   1. Soft-compressing extreme midpoint outliers (when `EnableOutlierCompression` is true).
	//   2. Applying `computeVarianceMult(sMid)` around each attribute's midpoint so lowborns
	//      roll wider stat ranges and highborns roll tighter, dependable stat ranges.
	function transformAttributeRanges( _rawAttrs )
	{
		if (_rawAttrs == null)
		{
			return _rawAttrs;
		}

		local p = ::BalancedBackgrounds.Params;
		local s0 = this.computeSSPFromAttrRanges(_rawAttrs);
		local compAttrs = _rawAttrs;

		if (p.EnableOutlierCompression && (s0 < p.LowOutlierThresholdSSP || s0 > p.HighOutlierThresholdSSP))
		{
			local scalePositive = s0 > p.HighOutlierThresholdSSP;
			local sTarget = scalePositive
				? ::Math.minf(p.HighOutlierCeilingSSP, p.HighOutlierThresholdSSP + p.HighOutlierSlope * (s0 - p.HighOutlierThresholdSSP))
				: ::Math.maxf(p.LowOutlierFloorSSP, p.LowOutlierThresholdSSP + p.LowOutlierSlope * (s0 - p.LowOutlierThresholdSSP));

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
			local floorVal = p.MinAttributeFloor[k];

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

	// Convert continuous star-curve position `_u` in [0.0, 1.0] and slot cap `_maxN` into
	// discrete-Gaussian `CountWeights` and `[1★, 2★, 3★]` `TierWeights` using `Params`.
	function paramsFromU( _u, _maxN )
	{
		local p = ::BalancedBackgrounds.Params;
		local u = this.clampFloat(_u, 0.0, 1.0);
		local anchorU = this.clampFloat(p.TargetAnchorU, 0.05, 0.95);
		local muN = p.TargetMeanTalents;
		local p1 = p.TargetStar1Pct;
		local p2 = p.TargetStar2Pct;

		if (u <= anchorU)
		{
			local t = u / anchorU;
			muN = p.HighbornMeanTalents + t * (p.TargetMeanTalents - p.HighbornMeanTalents);
			p1 = p.HighbornStar1Pct + t * (p.TargetStar1Pct - p.HighbornStar1Pct);
			p2 = p.HighbornStar2Pct + t * (p.TargetStar2Pct - p.HighbornStar2Pct);
		}
		else
		{
			local t = (u - anchorU) / (1.0 - anchorU);
			muN = p.TargetMeanTalents + t * (p.LowbornMeanTalents - p.TargetMeanTalents);
			p1 = p.TargetStar1Pct + t * (p.LowbornStar1Pct - p.TargetStar1Pct);
			p2 = p.TargetStar2Pct + t * (p.LowbornStar2Pct - p.TargetStar2Pct);
		}

		local sigmaN = ::Math.maxf(0.08, p.StarCountSigmaHighborn + u * (p.StarCountSigmaLowborn - p.StarCountSigmaHighborn));
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

		local tw1 = this.clampInt(this.roundInt(p1), 0, 100);
		local tw2 = this.clampInt(this.roundInt(p2), 0, 100 - tw1);
		local tw3 = ::Math.max(0, 100 - tw1 - tw2);

		return {
			CountWeights = countWeights,
			TierWeights = [ tw1, tw2, tw3 ]
		};
	},

	// Compute exact expected top-3 star SSP gain `G_top3(u)` for `_openAttrs` at curve coordinate `_u`
	// via a single-pass dynamic program over the open attributes.
	function computeExactGTop3AtU( _openAttrs, _u )
	{
		local m = _openAttrs.len();

		if (m == 0)
		{
			return 0.0;
		}

		local p = ::BalancedBackgrounds.Params;
		local maxN = p.LeaveAtLeastOneUntalentedAttr ? ::Math.max(0, m - 1) : m;
		local profile = this.paramsFromU(_u, maxN);
		local tw = profile.TierWeights;
		local tiers = [];

		if (tw[0] > 0) tiers.push([ 1, tw[0] * 0.01 ]);
		if (tw[1] > 0) tiers.push([ 2, tw[1] * 0.01 ]);
		if (tw[2] > 0) tiers.push([ 3, tw[2] * 0.01 ]);

		if (tiers.len() == 0)
		{
			return 0.0;
		}

		// Each star adds +5.0 expected stat over 10 levels, worth `5.0 * SSPWeights[attrKey]` SSP.
		// Quantize per-star SSP in units of 0.25 (`x4`, so `5.0 * w * 4 = 20.0 * w`) and pack
		// `(top1, top2, top3)` into a positive 32-bit integer `top1 * 1000000 + top2 * 1000 + top3`.
		local quantStarGain = [];

		foreach (attrIdx in _openAttrs)
		{
			local keyName = this.EnumToAttrKey[attrIdx];
			quantStarGain.push(this.clampInt(this.roundInt(20.0 * p.SSPWeights[keyName]), 0, 330));
		}

		// statesByCount[c] maps packed (top1 >= top2 >= top3) -> summed probability across C(m, c) subsets.
		local statesByCount = array(m + 1, null);

		for (local c = 0; c <= m; ++c)
		{
			statesByCount[c] = {};
		}

		statesByCount[0][0] <- 1.0;

		for (local idx = 0; idx < m; ++idx)
		{
			local w = quantStarGain[idx];

			for (local c = idx; c >= 0; --c)
			{
				local src = statesByCount[c];

				if (src.len() == 0)
				{
					continue;
				}

				local dst = statesByCount[c + 1];

				foreach (packedKey, probState in src)
				{
					local a = packedKey / 1000000;
					local b = (packedKey / 1000) % 1000;
					local d = packedKey % 1000;

					foreach (tier in tiers)
					{
						local g = tier[0] * w;
						local nextKey = packedKey;

						if (g >= a)
						{
							nextKey = g * 1000000 + a * 1000 + b;
						}
						else if (g >= b)
						{
							nextKey = a * 1000000 + g * 1000 + b;
						}
						else if (g >= d)
						{
							nextKey = a * 1000000 + b * 1000 + g;
						}

						if (nextKey in dst)
						{
							dst[nextKey] += probState * tier[1];
						}
						else
						{
							dst[nextKey] <- probState * tier[1];
						}
					}
				}
			}
		}

		local evByCount = array(m + 1, 0.0);

		for (local c = 1; c <= maxN; ++c)
		{
			local sumTop3 = 0.0;

			foreach (packedKey, probState in statesByCount[c])
			{
				local qSum = (packedKey / 1000000) + ((packedKey / 1000) % 1000) + (packedKey % 1000);
				sumTop3 += (qSum * 0.25) * probState;
			}

			evByCount[c] = sumTop3 / this.binomial(m, c);
		}

		local totalExpectedGain = 0.0;

		foreach (pair in profile.CountWeights)
		{
			local cnt = pair[0];

			if (cnt > 0 && cnt <= maxN)
			{
				totalExpectedGain += (pair[1] * 0.01) * evByCount[cnt];
			}
		}

		return totalExpectedGain;
	},

	// Build or retrieve the cached 101-point G_top3(u) lookup array (u = 0.00..1.00) for `_openAttrs`.
	// Evaluates `CurveSteps` (51) exact DP points and linearly interpolates odd hundredths.
	function getPoolCurve( _openAttrs )
	{
		local keyParts = [];

		foreach (idx in _openAttrs)
		{
			keyParts.push(idx.tostring());
		}

		local cacheKey = "";

		for (local i = 0; i < keyParts.len(); ++i)
		{
			cacheKey += (i == 0 ? "" : "_") + keyParts[i];
		}

		if (cacheKey in this.PoolCurveCache)
		{
			return this.PoolCurveCache[cacheKey];
		}

		local table = array(101, 0.0);

		for (local evenIdx = 0; evenIdx <= 100; evenIdx += 2)
		{
			table[evenIdx] = this.computeExactGTop3AtU(_openAttrs, evenIdx * 0.01);
		}

		for (local oddIdx = 1; oddIdx < 100; oddIdx += 2)
		{
			table[oddIdx] = 0.5 * (table[oddIdx - 1] + table[oddIdx + 1]);
		}

		this.PoolCurveCache[cacheKey] <- table;
		return table;
	},

	// Resolve `Params.TargetBackground` (e.g. `"militia_background"`) once at runtime to
	// determine its starting SSP (`StartSSP`) and natural Level-11 benchmark (`EndgameSSP`).
	function getTargetAnchor()
	{
		if (this.TargetAnchorCache != null)
		{
			return this.TargetAnchorCache;
		}

		local p = ::BalancedBackgrounds.Params;
		local startSSP = 23.30;
		local openAttrs = [ 0, 1, 2, 3, 4, 5, 6, 7 ];

		try
		{
			local bgScript = p.TargetBackground.find("scripts/") == 0
				? p.TargetBackground
				: "scripts/skills/backgrounds/" + p.TargetBackground;
			local targetBg = ::new(bgScript);

			// Read raw un-transformed midpoint SSP of the target benchmark background.
			::BalancedBackgrounds.Temp.CompressionDepth++;
			local rawAttrs = targetBg.onChangeAttributes();
			::BalancedBackgrounds.Temp.CompressionDepth--;

			startSSP = this.computeSSPFromAttrRanges(rawAttrs);
			local excluded = targetBg.getExcludedTalents();
			openAttrs = [];

			for (local i = 0; i < ::Const.Attributes.COUNT; ++i)
			{
				if (excluded.find(i) == null)
				{
					openAttrs.push(i);
				}
			}
		}
		catch (_err)
		{
			// Fallback to Vanilla Militia values if a custom TargetBackground name is invalid.
			startSSP = 23.30;
		}

		local anchorStep = this.clampInt(this.roundInt(p.TargetAnchorU * 100.0), 0, 100);
		local anchorCurve = this.getPoolCurve(openAttrs);
		local endgameSSP = startSSP + anchorCurve[anchorStep] + p.TargetBackgroundBonusSSP;

		this.TargetAnchorCache = {
			StartSSP = startSSP,
			EndgameSSP = endgameSSP
		};

		return this.TargetAnchorCache;
	},

	// Compute the Level-11 mean target SSP for a background with starting budget `_sAdj`
	// relative to `Params.TargetBackground` using `Params.EndgameMeanSlope`.
	function computeTargetEndgameSSP( _sAdj )
	{
		local anchor = this.getTargetAnchor();
		return anchor.EndgameSSP + ::BalancedBackgrounds.Params.EndgameMeanSlope * (_sAdj - anchor.StartSSP);
	},

	// Solve the star probability profile (CountWeights, TierWeights, OpenAttrs) for `_bg`
	// so `S_adj + G_top3(u)` matches `computeTargetEndgameSSP(S_adj)`.
	function getStarProfileForBackground( _bg )
	{
		local attrs = _bg != null ? _bg.onChangeAttributes() : null;
		local anchor = this.getTargetAnchor();
		local sAdj = attrs != null ? this.computeSSPFromAttrRanges(attrs) : anchor.StartSSP;
		local excluded = _bg != null ? _bg.getExcludedTalents() : [];

		local openAttrs = [];

		for (local i = 0; i < ::Const.Attributes.COUNT; ++i)
		{
			if (excluded.find(i) == null)
			{
				openAttrs.push(i);
			}
		}

		local p = ::BalancedBackgrounds.Params;
		local maxN = p.LeaveAtLeastOneUntalentedAttr ? ::Math.max(0, openAttrs.len() - 1) : openAttrs.len();
		local table = this.getPoolCurve(openAttrs);
		local desiredGain = this.computeTargetEndgameSSP(sAdj) - sAdj;

		local bestStep = this.clampInt(this.roundInt(p.TargetAnchorU * 100.0), 0, 100);
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

	// Roll an array of 8 talent star values (0..3) for `_actor` based on its background's profile.
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

		local maxAllowed = ::BalancedBackgrounds.Params.LeaveAtLeastOneUntalentedAttr
			? ::Math.max(0, openPool.len() - 1)
			: openPool.len();

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

		chosenN = this.clampInt(chosenN, 0, maxAllowed);

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

	// Roll the starting character level (`1 + pendingLevelUps`) for `_bg`.
	// Highborn backgrounds (`sAdj >= HighbornPendingLevelMinSSP`, excluding Origin Companions
	// and fixed Level-9 Crisis recruits) always start with 1..6 pending level-ups (`Level 2..7`).
	function rollStartingLevelForBackground( _bg )
	{
		if (_bg == null)
		{
			return 1;
		}

		local p = ::BalancedBackgrounds.Params;

		if (!p.EnableHighbornPendingLevels)
		{
			return _bg.m.Level;
		}

		// Preserve Day-1 Companion backgrounds and fixed Level-9 Crisis event recruits (Crusader / Orc Slayer).
		if (_bg.getID() == "background.companion" || _bg.m.Level >= 8)
		{
			return _bg.m.Level;
		}

		local attrs = _bg.onChangeAttributes();
		local sAdj = attrs != null ? this.computeSSPFromAttrRanges(attrs) : 0.0;

		if (sAdj < p.HighbornPendingLevelMinSSP)
		{
			return _bg.m.Level;
		}

		local minPending = this.clampInt(p.HighbornMinPendingLevels, 1, 6);
		local maxPending = this.clampInt(p.HighbornMaxPendingLevels, minPending, 6);
		local rawWeights = [
			p.PendingLevelWeight1,
			p.PendingLevelWeight2,
			p.PendingLevelWeight3,
			p.PendingLevelWeight4,
			p.PendingLevelWeight5,
			p.PendingLevelWeight6
		];

		local totalWeight = 0;

		for (local n = minPending; n <= maxPending; ++n)
		{
			totalWeight += ::Math.max(0, rawWeights[n - 1]);
		}

		if (totalWeight <= 0)
		{
			return 1 + minPending;
		}

		local r = ::Math.rand(1, totalWeight);
		local cumulative = 0;

		for (local n = minPending; n <= maxPending; ++n)
		{
			cumulative += ::Math.max(0, rawWeights[n - 1]);

			if (r <= cumulative)
			{
				return 1 + n;
			}
		}

		return 1 + maxPending;
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

	// Compute daily wage (crowns/day) purely from current BaseProperties using `Params`.
	function calcStatDailyWage( _actor )
	{
		local p = ::BalancedBackgrounds.Params;
		local bActor = this.computeActorBaseSSP(_actor);
		return ::Math.max(p.MinDailyWage, this.roundInt(p.DailyWageBase + p.DailyWagePerSSP * bActor));
	},

	// Compute equipment-free signing cost (crowns) from Level-1 BaseProperties plus Vanilla's
	// power-law surcharge `floor(PendingLevelCostMult * (Level - 1)^PendingLevelCostExp)`.
	function calcBaseHiringCost( _actor )
	{
		local p = ::BalancedBackgrounds.Params;
		local bActor = this.computeActorBaseSSP(_actor);
		local pendingLevels = ::Math.max(0, _actor.getLevel() - 1);
		local level1Cost = ::Math.maxf(20.0, p.HiringCostBaseMult * 10.0 * ::Math.pow(this.EulerE, p.HiringCostExpSlope * bActor));
		local pendingCost = pendingLevels > 0
			? ::Math.floor(p.PendingLevelCostMult * ::Math.pow(pendingLevels, p.PendingLevelCostExp))
			: 0.0;
		return 10 * ::Math.ceil((level1Cost + pendingCost) * 0.1).tointeger();
	},

	// Compute equipped signing cost (crowns): BaseHiringCost + markup * item value, rounded up to 10c.
	function calcEquippedHiringCost( _actor, _baseHiringCost )
	{
		local items = _actor.getItems().getAllItems();
		local equipCost = 0.0;

		foreach (item in items)
		{
			equipCost += item.getValue();
		}

		equipCost *= ::BalancedBackgrounds.Params.EquipmentHiringMarkup;
		return 10 * ::Math.ceil((_baseHiringCost + equipCost) * 0.1).tointeger();
	}
};
