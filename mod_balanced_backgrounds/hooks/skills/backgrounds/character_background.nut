// =========================================================================================
// Balanced Backgrounds - Character Background Hooks
// =========================================================================================
// Hooks both the exact `character_background` base class and all background subclasses:
//   - Base class hooks:
//       * `onAdded` / `onDeserialize`: remove Vanilla's hidden `DailyCost += 1` bump and
//         random `0.90..1.10` `DailyCostMult` variance so wages depend solely on stats.
//       * `onUpdate`: compute `DailyWage` purely from `BaseProperties` (preserving Avatar
//         0-wage rules, Manhunters unpaid Indebted rules, and flat event wage modifiers).
//       * `adjustHiringCostBasedOnEquipment`: set `BaseHiringCost` and equipped `HiringCost`.
//   - Subclass tree hooks:
//       * `create`: filter `ExcludedTalents` down to at most 1 thematic flaw.
//       * `onChangeAttributes`: soft-compress extreme starting stat midpoints and apply the
//         linear lowborn-to-highborn attribute roll variance curve (automatically updating
//         Reforged's base attribute range tooltips as well).
// =========================================================================================

::BalancedBackgrounds.hook("scripts/skills/backgrounds/character_background", function( q )
{
	// Roll Highborn starting pending level-ups (1..6 -> Level 2..7) for newly generated recruits
	// outside Day-1 Origin scenario spawns, and prevent Vanilla's `onAdded` from incrementing
	// `DailyCost` or applying random `0.90..1.10` wage jitter.
	q.onAdded = @(__original) function()
	{
		local isScenarioMode = ("State" in ::Tactical) && ::Tactical.State != null && ::Tactical.State.isScenarioMode();

		if (this.m.IsNew && ::BalancedBackgrounds.Temp.ScenarioSpawnDepth == 0 && !isScenarioMode)
		{
			this.m.Level = ::BalancedBackgrounds.Math.rollStartingLevelForBackground(this);
		}

		local savedDailyCost = this.m.DailyCost;
		__original();
		this.m.DailyCost = savedDailyCost;
		this.m.DailyCostMult = 1.0;
	};

	// Replace background preset wage compounding with pure BaseProperties-driven daily wages.
	q.onUpdate = @() function( _properties )
	{
		local isManhunterOrigin = ("State" in ::World)
			&& ::World.State != null
			&& ::World.Assets.getOrigin() != null
			&& ::World.Assets.getOrigin().getID() == "scenario.manhunters";

		local isUnpaidAvatarOrManhunterSlave = this.getContainer().hasSkill("trait.player")
			|| (isManhunterOrigin && this.getID() == "background.slave");

		if (isUnpaidAvatarOrManhunterSlave)
		{
			_properties.DailyWage = 0;
		}
		else
		{
			// Use `+=` so flat wage adjustments stored on BaseProperties.DailyWage by events
			// (such as raise demands) continue to apply on top of the stat-based wage.
			local actor = this.getContainer().getActor();
			_properties.DailyWage += ::BalancedBackgrounds.Math.calcStatDailyWage(actor);
		}

		// Preserve Vanilla's non-Indebted XP penalty for the Manhunters origin.
		if (isManhunterOrigin && this.getID() != "background.slave")
		{
			_properties.XPGainMult *= 0.9;
		}
	};

	// Compute both equipment-free `BaseHiringCost` and equipped `HiringCost` from BaseProperties.
	q.adjustHiringCostBasedOnEquipment = @() function()
	{
		local actor = this.getContainer().getActor();
		local baseCost = ::BalancedBackgrounds.Math.calcBaseHiringCost(actor);
		actor.m.BaseHiringCost = baseCost;
		actor.m.HiringCost = ::BalancedBackgrounds.Math.calcEquippedHiringCost(actor, baseCost);
	};

	// Normalize deserialized `DailyCostMult` on existing saves so wages stay deterministic.
	q.onDeserialize = @(__original) function( _in )
	{
		__original(_in);
		this.m.DailyCostMult = 1.0;
	};
});

::BalancedBackgrounds.hookTree("scripts/skills/backgrounds/character_background", function( q )
{
	// Filter `ExcludedTalents` once the outermost subclass `create()` finishes initializing `m.ID`.
	q.create = @(__original) function()
	{
		::BalancedBackgrounds.Temp.CreateDepth++;
		__original();
		::BalancedBackgrounds.Temp.CreateDepth--;

		if (::BalancedBackgrounds.Temp.CreateDepth == 0)
		{
			this.m.DailyCostMult = 1.0;
			this.m.ExcludedTalents = ::BalancedBackgrounds.Math.filterExcludedTalents(this.m.ID, this.m.ExcludedTalents);
		}
	};

	// Transform `onChangeAttributes()` ranges once at the outer call level (outlier midpoint
	// compression + linear starting attribute roll variance).
	q.onChangeAttributes = @(__original) function()
	{
		if (::BalancedBackgrounds.Temp.CompressionDepth > 0)
		{
			return __original();
		}

		::BalancedBackgrounds.Temp.CompressionDepth++;
		local rawDeltas = __original();
		::BalancedBackgrounds.Temp.CompressionDepth--;

		return ::BalancedBackgrounds.Math.transformAttributeRanges(rawDeltas);
	};
});
