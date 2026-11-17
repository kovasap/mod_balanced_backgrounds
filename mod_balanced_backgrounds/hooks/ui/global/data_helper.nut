// =========================================================================================
// Balanced Backgrounds - UI Hire Data Helper Hook
// =========================================================================================
// Appends equipment-free hiring cost metadata (`FullMoneyCost`, `NoEquipMoneyCost`, and
// `HasEquipment`) to each settlement recruit's UI payload so `WorldTownScreenHireDialogModule`
// can live-toggle between equipped and unequipped upfront prices.
// =========================================================================================

::BalancedBackgrounds.hook("scripts/ui/global/data_helper", function( q )
{
	// Extend the recruit UI payload with both equipped and equipment-free signing prices.
	q.convertEntityHireInformationToUIData = @(__original) function( _entity )
	{
		local ret = __original(_entity);

		if (ret == null || _entity == null || _entity.getBackground() == null)
		{
			return ret;
		}

		local mult = (("State" in ::World) && ::World.State != null && ::World.Assets != null) ? ::World.Assets.m.HiringCostMult : 1.0;
		ret.FullMoneyCost <- ret.InitialMoneyCost;
		ret.NoEquipMoneyCost <- ::Math.ceil(_entity.getBaseHiringCost() * mult).tointeger();
		ret.HasEquipment <- _entity.getItems().getAllItems().len() > 0;

		return ret;
	};
});
