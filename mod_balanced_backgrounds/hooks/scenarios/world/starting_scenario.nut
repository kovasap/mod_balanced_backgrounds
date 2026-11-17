// =========================================================================================
// Balanced Backgrounds - Starting Origin Scenario Hooks
// =========================================================================================
// Many starting scenarios (`lone_wolf`, `gladiators`, `raiders`, `paladins`, `anatomists`,
// `deserters`, `rangers`, `trader`, `manhunters`, `beast_hunters`, etc.) manually overwrite
// `bro.m.Talents` in `onSpawnAssets()` after calling `setStartValuesEx()`.
//
// Hooking `onSpawnAssets()` across the `starting_scenario` tree detects any Day-1 roster
// character whose talents were hardcoded or skipped and re-rolls their stars & level-up
// table using Balanced Backgrounds' solver. Because `onSpawnAssets()` runs before
// `onSpawnPlayer()`, Reforged's dynamic perk tree rebuild in `onSpawnPlayer()` automatically
// sees the newly rolled stars.
// =========================================================================================

// Check whether two 8-attribute talent arrays contain identical star values.
local function talentsMatch( _a, _b )
{
	if (_a == null || _b == null || _a.len() != _b.len() || _a.len() != ::Const.Attributes.COUNT)
	{
		return false;
	}

	for (local i = 0; i < _a.len(); ++i)
	{
		if (_a[i] != _b[i])
		{
			return false;
		}
	}

	return true;
}

::BalancedBackgrounds.hookTree("scripts/scenarios/world/starting_scenario", function( q )
{
	// Re-roll hardcoded starting roster talents at the end of `onSpawnAssets()`.
	q.onSpawnAssets = @(__original) function()
	{
		__original();

		local scenarioID = this.getID();

		// Reforged's Random Solo / Random Trio origins already roll talents via `setStartValuesEx`
		// (using our `fillTalentValues`) and upgrade rolled slots to 3-star / 2-star by design.
		if (scenarioID == "scenario.rf_random_solo" || scenarioID == "scenario.rf_random_trio")
		{
			return;
		}

		if (!("State" in ::World) || ::World.State == null || ::World.getPlayerRoster() == null)
		{
			return;
		}

		foreach (bro in ::World.getPlayerRoster().getAll())
		{
			local bg = bro.getBackground();

			if (bg == null || bg.isUntalented())
			{
				continue;
			}

			if (!("BB_RolledTalents" in bro.m) || !talentsMatch(bro.getTalents(), bro.m.BB_RolledTalents))
			{
				bro.m.Talents = [];
				bro.fillTalentValues();
				bro.m.Attributes = [];
				bro.fillAttributeLevelUpValues(::Const.XP.MaxLevelWithPerkpoints - 1);
			}
		}
	};
});
