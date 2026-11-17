// =========================================================================================
// Balanced Backgrounds - Player Entity Hooks
// =========================================================================================
// Hooks `scripts/entity/tactical/player` to:
//   1. Store and lazily compute equipment-free `BaseHiringCost` (requiring zero custom
//      save-file serialization so the mod can be added/removed mid-campaign safely).
//   2. Replace Vanilla's fixed 3-attribute `60/30/10` `fillTalentValues()` with the
//      background-calibrated Balanced Backgrounds star roller.
//   3. Scale `getTryoutCost()` from `BaseHiringCost` rather than equipped `HiringCost`,
//      so trying out an armored recruit prices the man rather than his armor.
// =========================================================================================

::BalancedBackgrounds.hook("scripts/entity/tactical/player", function( q )
{
	q.m.BaseHiringCost <- 0;
	q.m.BB_RolledTalents <- null;

	// Return the recruit's equipment-free signing cost, computing it lazily if loaded from a save.
	q.getBaseHiringCost <- function()
	{
		if (this.m.BaseHiringCost <= 0)
		{
			this.m.BaseHiringCost = ::BalancedBackgrounds.Math.calcBaseHiringCost(this);
		}

		return this.m.BaseHiringCost;
	};

	// Roll talent count N and star tiers (1-3 stars) calibrated to this character's background.
	q.fillTalentValues = @() function()
	{
		this.m.Talents = ::BalancedBackgrounds.Math.rollTalentsForActor(this);
		this.m.BB_RolledTalents = clone this.m.Talents;
	};

	// Calculate tryout cost from equipment-free `BaseHiringCost`, respecting Hardened's
	// `TryoutCostPct` when present or Vanilla's 10% rate otherwise.
	q.getTryoutCost = @() function()
	{
		local baseCost = this.getBaseHiringCost();
		local pct = ("TryoutCostPct" in ::Const.World.Assets) ? ::Const.World.Assets.TryoutCostPct : 0.1;
		local mult = (("State" in ::World) && ::World.State != null && ::World.Assets != null) ? ::World.Assets.m.TryoutPriceMult : 1.0;
		local tryoutCost = (25.0 + baseCost * pct) * mult;
		return ::Math.ceil(::Math.maxf(10.0, ::Math.minf(baseCost - 25.0, tryoutCost))).tointeger();
	};
});
