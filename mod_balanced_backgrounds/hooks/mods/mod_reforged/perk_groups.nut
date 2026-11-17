// =========================================================================================
// Balanced Backgrounds - Reforged Special Perk Group Compatibility Hooks
// =========================================================================================
// In Reforged, `pg.special.rf_man_of_steel` and `pg.special.rf_marksmanship` normally scale
// their spawn weight by `talents[Fatigue]` and `talents[RangedSkill]`, returning `0` when a
// recruit has 0 stars in that attribute.
//
// Because Balanced Backgrounds assigns fewer stars to high-starting-stat elites (such as
// Hedge Knights or Master Archers), this hook grants a base `1x` eligibility weight when a
// 0-star recruit's projected Level-11 Fatigue (>= 130) or RangedSkill (>= 85) is already high.
// =========================================================================================

if (::BalancedBackgrounds.hasMod("mod_reforged"))
{
	::BalancedBackgrounds.hook("scripts/mods/mod_reforged/perk_groups/special/pg_special_rf_man_of_steel", function( q )
	{
		// Keep Man of Steel eligible on 0-star heavy-armor recruits with >= 130 projected Fatigue.
		q.getSelfMultiplier = @(__original) function( _perkTree )
		{
			local ret = __original(_perkTree);

			if (ret == 0 && _perkTree.hasPerkGroup("pg.rf_heavy_armor") && _perkTree.getProjectedAttributesAvg()[::Const.Attributes.Fatigue] >= 130)
			{
				return 1;
			}

			return ret;
		};
	});

	::BalancedBackgrounds.hook("scripts/mods/mod_reforged/perk_groups/special/pg_special_rf_marksmanship", function( q )
	{
		// Keep Marksmanship eligible on 0-star ranged recruits with >= 85 projected Ranged Skill.
		q.getSelfMultiplier = @(__original) function( _perkTree )
		{
			local ret = __original(_perkTree);

			if (ret == 0 && _perkTree.hasPerkGroup("pg.rf_ranged") && _perkTree.getProjectedAttributesAvg()[::Const.Attributes.RangedSkill] >= 85)
			{
				return 1;
			}

			return ret;
		};
	});
}
