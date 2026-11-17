// =========================================================================================
// Balanced Backgrounds - Town Hire Dialog Backend Handler
// =========================================================================================
// Adds `onHireRosterEntryWithoutEquipment(_entityID)` to `town_hire_dialog_module` (affecting
// only town recruits, never Campfire Retinue followers).
//
// When the player unchecks "Include Equipment" in the Town Hire Screen, this handler verifies
// roster space and crowns against the recruit's equipment-free `NoEquipMoneyCost`, strips all
// equipped and bag items (refreshing sprites and skill properties), adds the recruit to the
// player company, and deducts only the base signing cost.
// =========================================================================================

::BalancedBackgrounds.hook("scripts/ui/screens/world/modules/world_town_screen/town_hire_dialog_module", function( q )
{
	// Hire a settlement recruit without their starting equipment for their base signing cost.
	q.onHireRosterEntryWithoutEquipment <- function( _entityID )
	{
		local entity = this.findEntityWithinRoster(_entityID);

		if (entity == null)
		{
			return {
				Result = ::Const.UI.Error.RosterEntryNotFound,
				Assets = null
			};
		}

		local hiringCost = ::Math.ceil(entity.getBaseHiringCost() * ::World.Assets.m.HiringCostMult).tointeger();

		if (::World.Assets.getMoney() < hiringCost)
		{
			return {
				Result = ::Const.UI.Error.NotEnoughMoney,
				Assets = null
			};
		}

		if (::World.getPlayerRoster().getAll().len() + 1 > ::World.Assets.getBrothersMax())
		{
			return {
				Result = ::Const.UI.Error.NotEnoughRosterSpace,
				Assets = null
			};
		}

		// Unequip and remove all starting gear & bag items, then refresh character sprites.
		entity.getItems().clear();
		entity.getItems().updateAppearance();

		::World.getPlayerRoster().add(entity);
		::World.getRoster(this.m.RosterID).remove(entity);
		entity.onHired();
		entity.getSkills().update();

		::World.Assets.addMoney(-hiringCost);
		::World.Statistics.getFlags().increment("BrosHired");

		if (::World.getRoster(this.m.RosterID).getSize() == 0)
		{
			this.m.Parent.getMainDialogModule().reload();
		}

		return {
			Result = 0,
			Assets = this.m.Parent.queryAssetsInformation()
		};
	};
});
