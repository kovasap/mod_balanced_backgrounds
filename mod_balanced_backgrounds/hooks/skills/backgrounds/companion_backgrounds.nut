// =========================================================================================
// Balanced Backgrounds - Companion Origin Background Hooks
// =========================================================================================
// In Vanilla Battle Brothers, the 6 starting Companion background variants (`1h`, `2h`,
// `ranged`, and their Southern counterparts) set `m.IsUntalented = true` and hardcode fixed
// `[2, 1, 1]` talent stars inside `onAddEquipment()`.
//
// This hook enables normal talent rolling on Companions and preserves rolled talents across
// `onAddEquipment()` while still equipping their starting weapons, shields, and armor.
// =========================================================================================

local companionScripts = [
	"scripts/skills/backgrounds/companion_1h_background",
	"scripts/skills/backgrounds/companion_1h_southern_background",
	"scripts/skills/backgrounds/companion_2h_background",
	"scripts/skills/backgrounds/companion_2h_southern_background",
	"scripts/skills/backgrounds/companion_ranged_background",
	"scripts/skills/backgrounds/companion_ranged_southern_background"
];

foreach (scriptPath in companionScripts)
{
	::BalancedBackgrounds.hook(scriptPath, function( q )
	{
		// Allow Companion backgrounds to roll stars via Balanced Backgrounds' solver.
		q.create = @(__original) function()
		{
			__original();
			this.m.IsUntalented = false;
			this.m.ExcludedTalents = ::BalancedBackgrounds.Math.filterExcludedTalents(this.m.ID, this.m.ExcludedTalents);
		};

		// Equip starting Companion gear without letting Vanilla overwrite `actor.m.Talents`.
		q.onAddEquipment = @(__original) function()
		{
			local actor = this.getContainer().getActor();
			local savedTalents = clone actor.getTalents();
			__original();
			actor.m.Talents = savedTalents;
		};
	});
}
