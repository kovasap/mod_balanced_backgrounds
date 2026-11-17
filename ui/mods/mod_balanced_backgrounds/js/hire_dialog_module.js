/* =========================================================================================
 * Balanced Backgrounds - Town Hire Dialog Frontend Hook (`WorldTownScreenHireDialogModule`)
 * =========================================================================================
 * Adds an "Include Equipment" checkbox (checked by default) to the Town Hire Screen:
 *   - When checked, recruits display and charge `FullMoneyCost` (base signing cost + gear).
 *   - When unchecked, recruits display and charge `NoEquipMoneyCost` (base signing cost only)
 *     across both the left-hand roster list cards and the right-hand details panel, updating
 *     affordability colors and the `HireButton` enabled state automatically.
 *   - Routes hiring calls to `onHireRosterEntryWithoutEquipment` when unchecked.
 * ========================================================================================= */

var BalancedBackgrounds = window.BalancedBackgrounds || { Hooks: {} };
window.BalancedBackgrounds = BalancedBackgrounds;

WorldTownScreenHireDialogModule.prototype.mIncludeEquipment = true;
WorldTownScreenHireDialogModule.prototype.mIncludeEquipmentContainer = null;
WorldTownScreenHireDialogModule.prototype.mIncludeEquipmentCheckbox = null;

// Format crown amounts with thousands separators using Battle Brothers' Helper when present.
WorldTownScreenHireDialogModule.prototype.bbFormatMoney = function (_value)
{
	if (typeof Helper !== 'undefined' && Helper !== null && typeof Helper.numberWithCommas === 'function')
	{
		return Helper.numberWithCommas(_value);
	}
	return '' + _value;
};

// Synchronize `_entry.InitialMoneyCost` with the active "Include Equipment" toggle state.
// Because Vanilla's own `updateListEntryValues` and `updateDetailsPanel` read `InitialMoneyCost`,
// updating this field lets Vanilla (plus Reforged/Hardened hooks) handle red/white affordability
// text styling and `HireButton` enablement automatically.
WorldTownScreenHireDialogModule.prototype.bbApplyEquipmentCostModeToEntry = function (_entry)
{
	if (_entry === null || _entry === undefined)
	{
		return;
	}

	if (_entry['FullMoneyCost'] === undefined)
	{
		_entry['FullMoneyCost'] = _entry['InitialMoneyCost'];
	}

	if (_entry['NoEquipMoneyCost'] === undefined)
	{
		_entry['NoEquipMoneyCost'] = _entry['FullMoneyCost'];
	}

	_entry['InitialMoneyCost'] = this.mIncludeEquipment ? _entry['FullMoneyCost'] : _entry['NoEquipMoneyCost'];
};

// Handle user clicks on the "Include Equipment" checkbox and refresh all displayed prices.
WorldTownScreenHireDialogModule.prototype.onIncludeEquipmentToggled = function (_checked)
{
	this.mIncludeEquipment = !!_checked;
	this.updateListEntryValues();
	this.updateDetailsPanel(this.mSelectedEntry);
};

// Inject the "Include Equipment" checkbox and native tooltip when creating the Hire Dialog DOM.
BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_createDIV = WorldTownScreenHireDialogModule.prototype.createDIV;
WorldTownScreenHireDialogModule.prototype.createDIV = function (_parentDiv)
{
	BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_createDIV.call(this, _parentDiv);

	var self = this;
	this.mIncludeEquipment = true;

	var footerContainer = null;
	if (this.mDialogContainer !== null && typeof this.mDialogContainer.findDialogFooterContainer === 'function')
	{
		footerContainer = this.mDialogContainer.findDialogFooterContainer();
	}
	if ((footerContainer === null || footerContainer.length === 0) && this.mDetailsPanel && this.mDetailsPanel.Container)
	{
		footerContainer = this.mDetailsPanel.Container;
	}

	if (footerContainer !== null && footerContainer.length > 0)
	{
		this.mIncludeEquipmentContainer = $('<div class="bb-include-equipment-container"/>');
		this.mIncludeEquipmentCheckbox = $('<input type="checkbox" class="bb-include-equipment-checkbox" id="cb-bb-include-equipment" checked="checked"/>');
		var label = $('<label class="text-font-normal font-color-subtitle bb-include-equipment-label" for="cb-bb-include-equipment">Include Equipment</label>');

		this.mIncludeEquipmentContainer.append(this.mIncludeEquipmentCheckbox);
		this.mIncludeEquipmentContainer.append(label);
		footerContainer.append(this.mIncludeEquipmentContainer);

		if (typeof this.mIncludeEquipmentCheckbox.iCheck === 'function')
		{
			this.mIncludeEquipmentCheckbox.iCheck({
				checkboxClass: 'icheckbox_flat-orange',
				radioClass: 'iradio_flat-orange',
				increaseArea: '30%'
			});

			this.mIncludeEquipmentCheckbox.on('ifChecked ifUnchecked', null, this, function (_event)
			{
				self.onIncludeEquipmentToggled(_event.type === 'ifChecked');
			});
		}
		else
		{
			this.mIncludeEquipmentCheckbox.on('change', function ()
			{
				self.onIncludeEquipmentToggled(self.mIncludeEquipmentCheckbox.prop('checked') === true);
			});
		}

		if (typeof this.mIncludeEquipmentContainer.bindTooltip === 'function')
		{
			this.mIncludeEquipmentContainer.bindTooltip({
				contentType: 'ui-element',
				elementId: 'world-town-screen.hire-dialog-module.IncludeEquipmentCheckbox'
			});
		}
	}
};

// Clean up checkbox DOM elements and tooltips when destroying the Hire Dialog.
BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_destroyDIV = WorldTownScreenHireDialogModule.prototype.destroyDIV;
WorldTownScreenHireDialogModule.prototype.destroyDIV = function ()
{
	if (this.mIncludeEquipmentContainer !== null)
	{
		if (typeof this.mIncludeEquipmentContainer.unbindTooltip === 'function')
		{
			this.mIncludeEquipmentContainer.unbindTooltip();
		}
		this.mIncludeEquipmentContainer.remove();
		this.mIncludeEquipmentContainer = null;
	}
	this.mIncludeEquipmentCheckbox = null;

	BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_destroyDIV.call(this);
};

// Apply the active price mode before rendering a recruit card and cache its upfront price element.
BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_addListEntry = WorldTownScreenHireDialogModule.prototype.addListEntry;
WorldTownScreenHireDialogModule.prototype.addListEntry = function (_data)
{
	this.bbApplyEquipmentCostModeToEntry(_data);
	BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_addListEntry.call(this, _data);

	if (!this.mListScrollContainer)
	{
		return;
	}

	var lastRow = this.mListScrollContainer.children().last();
	if (!lastRow || lastRow.length === 0)
	{
		return;
	}

	var priceLabel = lastRow.find('img[src*="money.png"]:not([src*="daily"])').parent().find('.label:first');
	if (!priceLabel || priceLabel.length === 0)
	{
		var expectedFormatted = this.bbFormatMoney(_data['InitialMoneyCost']);
		var expectedRaw = '' + _data['InitialMoneyCost'];
		lastRow.find('*').each(function ()
		{
			var el = $(this);
			if (el.children().length === 0)
			{
				var txt = $.trim(el.text());
				if (txt === expectedFormatted || txt === expectedRaw)
				{
					priceLabel = el;
					return false;
				}
			}
		});
	}

	if (priceLabel && priceLabel.length > 0)
	{
		lastRow.data('bb-price-label', priceLabel);
	}
};

// Refresh upfront crown labels on every roster card whenever money or the gear toggle changes.
BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_updateListEntryValues = WorldTownScreenHireDialogModule.prototype.updateListEntryValues;
WorldTownScreenHireDialogModule.prototype.updateListEntryValues = function ()
{
	var self = this;

	if (this.mRoster && this.mRoster.length)
	{
		for (var i = 0; i < this.mRoster.length; ++i)
		{
			this.bbApplyEquipmentCostModeToEntry(this.mRoster[i]);
		}
	}

	if (this.mListScrollContainer)
	{
		this.mListScrollContainer.children().each(function ()
		{
			var row = $(this);
			var listEntry = row.hasClass('list-entry') ? row : row.find('.list-entry:first');
			var entry = listEntry.length > 0 ? listEntry.data('entry') : row.data('entry');
			if (entry)
			{
				self.bbApplyEquipmentCostModeToEntry(entry);
				var priceLabel = row.data('bb-price-label');
				if (priceLabel && priceLabel.length > 0)
				{
					priceLabel.html(self.bbFormatMoney(entry['InitialMoneyCost']));
				}
			}
		});
	}

	BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_updateListEntryValues.call(this);
};

// Ensure the selected recruit's entry reflects the active price mode before updating details.
BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_updateDetailsPanel = WorldTownScreenHireDialogModule.prototype.updateDetailsPanel;
WorldTownScreenHireDialogModule.prototype.updateDetailsPanel = function (_element)
{
	if (_element !== null && _element !== undefined && _element.length > 0)
	{
		this.bbApplyEquipmentCostModeToEntry(_element.data('entry'));
	}

	BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_updateDetailsPanel.call(this, _element);
};

// Route backend hire calls to `onHireRosterEntryWithoutEquipment` when "Include Equipment" is off.
if (typeof WorldTownScreenHireDialogModule.prototype.notifyBackendHireRosterEntry === 'function')
{
	BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_notifyBackendHireRosterEntry = WorldTownScreenHireDialogModule.prototype.notifyBackendHireRosterEntry;
	WorldTownScreenHireDialogModule.prototype.notifyBackendHireRosterEntry = function (_entryID, _callback)
	{
		if (!this.mIncludeEquipment)
		{
			SQ.call(this.mSQHandle, 'onHireRosterEntryWithoutEquipment', _entryID, _callback);
			return;
		}

		BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_notifyBackendHireRosterEntry.call(this, _entryID, _callback);
	};
}
else
{
	BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_hireRosterEntry = WorldTownScreenHireDialogModule.prototype.hireRosterEntry;
	WorldTownScreenHireDialogModule.prototype.hireRosterEntry = function (_entryID)
	{
		if (this.mIncludeEquipment)
		{
			BalancedBackgrounds.Hooks.WorldTownScreenHireDialogModule_hireRosterEntry.call(this, _entryID);
			return;
		}

		var self = this;
		SQ.call(this.mSQHandle, 'onHireRosterEntryWithoutEquipment', _entryID, function (_data)
		{
			if (_data === null || _data.Result !== 0)
			{
				return;
			}

			for (var i = 0; i < self.mRoster.length; ++i)
			{
				if (self.mRoster[i]['ID'] == _entryID)
				{
					self.removeRosterEntry({ item: self.mRoster[i], index: i });
					break;
				}
			}

			self.mParent.loadAssetData(_data.Assets);
			self.updateListEntryValues();
			self.updateDetailsPanel(self.mSelectedEntry);
		});
	};
}
