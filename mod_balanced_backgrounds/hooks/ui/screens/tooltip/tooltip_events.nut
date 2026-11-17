// =========================================================================================
// Balanced Backgrounds - Native UI Element Tooltip Hook
// =========================================================================================
// Provides a native Battle Brothers `ui-element` tooltip for the "Include Equipment" toggle
// in the Town Hire Screen so tooltips work cleanly with or without MSU installed.
// =========================================================================================

::BalancedBackgrounds.hook("scripts/ui/screens/tooltip/tooltip_events", function( q )
{
	// Return title and description tooltip entries for the Hire Screen equipment toggle.
	q.general_queryUIElementTooltipData = @(__original) function( _entityId, _elementId, _elementOwner )
	{
		if (_elementId == "world-town-screen.hire-dialog-module.IncludeEquipmentCheckbox")
		{
			return [
				{
					id = 1,
					type = "title",
					text = "Include Equipment"
				},
				{
					id = 2,
					type = "description",
					text = "Hire recruits together with their starting weapons and armor. Uncheck to hire recruits without any equipment for their base signing cost alone."
				}
			];
		}

		return __original(_entityId, _elementId, _elementOwner);
	};
});
