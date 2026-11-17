// =========================================================================================
// Balanced Backgrounds - Mod Preload & Hook Loader
// =========================================================================================
// Registers the mod, integrates with MSU when available, and provides a unified hooking API
// that supports both Modern Hooks (::Hooks, used by Reforged and Hardened) and legacy
// mod_hooks (::mods_registerMod, used in standalone Vanilla / XBE setups).
//
// All hooks are queued in a late load-order bucket after MSU, Modular Vanilla, Dynamic Perks,
// Reforged, Hardened, and More Backgrounds & Events (XBE) so dynamic attribute evaluations
// automatically reflect any background changes made by other mods.
// =========================================================================================

::BalancedBackgrounds <- {
	ID = "mod_balanced_backgrounds",
	Version = "1.0.0",
	Name = "Balanced Backgrounds",
	GitHubURL = "https://github.com/kovasap/mod_balanced_backgrounds",

	// Re-entrancy counters used when wrapping inherited background methods (create / onChangeAttributes)
	// so parent-to-child super calls only apply filtering or stat compression once at the outer call.
	Temp = {
		CreateDepth = 0,
		CompressionDepth = 0
	}
};

local loadOrder = [
	">msu",
	">mod_modular_vanilla",
	">mod_dynamic_perks",
	">mod_reforged",
	">mod_hardened",
	">mod_backgrounds_and_events"
];

// Register frontend CSS and JS hooks for the Town Hire Screen "Include Equipment" toggle.
local function registerUI()
{
	local cssPath = "ui/mods/mod_balanced_backgrounds/css/hire_dialog_module.css";
	local jsPath = "ui/mods/mod_balanced_backgrounds/js/hire_dialog_module.js";

	if ("Hooks" in ::getroottable())
	{
		::Hooks.registerCSS(cssPath);
		::Hooks.registerJS(jsPath);
	}
	else
	{
		::mods_registerCSS(cssPath);
		::mods_registerJS(jsPath);
	}
}

// Entrypoint executed once all upstream overhaul/background mods have registered their scripts.
local function loadModFiles()
{
	if ("MSU" in ::getroottable())
	{
		::BalancedBackgrounds.Mod <- ::MSU.Class.Mod(::BalancedBackgrounds.ID, ::BalancedBackgrounds.Version, ::BalancedBackgrounds.Name);
		::BalancedBackgrounds.Mod.Registry.addModSource(::MSU.System.Registry.ModSourceDomain.GitHub, ::BalancedBackgrounds.GitHubURL);
		::BalancedBackgrounds.Mod.Registry.setUpdateSource(::MSU.System.Registry.ModSourceDomain.GitHub);
	}

	::include("mod_balanced_backgrounds/config/balance_math");
	::include("mod_balanced_backgrounds/hooks/skills/backgrounds/character_background");
	::include("mod_balanced_backgrounds/hooks/skills/backgrounds/companion_backgrounds");
	::include("mod_balanced_backgrounds/hooks/entity/tactical/player");
	::include("mod_balanced_backgrounds/hooks/scenarios/world/starting_scenario");
	::include("mod_balanced_backgrounds/hooks/mods/mod_reforged/perk_groups");
	::include("mod_balanced_backgrounds/hooks/ui/global/data_helper");
	::include("mod_balanced_backgrounds/hooks/ui/screens/world/modules/world_town_screen/town_hire_dialog_module");
	::include("mod_balanced_backgrounds/hooks/ui/screens/tooltip/tooltip_events");

	registerUI();
}

if ("Hooks" in ::getroottable())
{
	::BalancedBackgrounds.HooksMod <- ::Hooks.register(::BalancedBackgrounds.ID, ::BalancedBackgrounds.Version, ::BalancedBackgrounds.Name);

	// Check whether an optional mod (such as Reforged) is active in the current load order.
	::BalancedBackgrounds.hasMod <- function( _modID )
	{
		return ::Hooks.hasMod(_modID);
	};

	// Hook a single exact script class using Modern Hooks semantics: _fn(q).
	::BalancedBackgrounds.hook <- function( _script, _fn )
	{
		::BalancedBackgrounds.HooksMod.hook(_script, _fn);
	};

	// Hook a base script class and all classes inheriting from it: _fn(q).
	::BalancedBackgrounds.hookTree <- function( _script, _fn )
	{
		::BalancedBackgrounds.HooksMod.hookTree(_script, _fn);
	};

	::BalancedBackgrounds.HooksMod.queue(loadOrder, loadModFiles, ::Hooks.QueueBucket.Late);
}
else
{
	::mods_registerMod(::BalancedBackgrounds.ID, ::BalancedBackgrounds.Version, ::BalancedBackgrounds.Name);

	// Legacy mod_hooks expects paths without the leading "scripts/" prefix.
	local function stripScriptsPrefix( _script )
	{
		return _script.find("scripts/") == 0 ? _script.slice(8) : _script;
	}

	// Lightweight adapter allowing Modern Hooks style `q.method = @(__original) ...` definitions
	// to run seamlessly on legacy mod_hooks environments without duplicating hook files.
	local function applyLegacyHook( _target, _fn )
	{
		local proxy = {}.setdelegate({
			_get = function( _k )
			{
				return _target[_k];
			},
			_set = function( _k, _v )
			{
				if ((_k in _target) && typeof _target[_k] == "function" && typeof _v == "function")
				{
					local oldFn = _target[_k];
					local numParams = _v.getinfos().parameters.len();
					_target[_k] = numParams >= 2 ? _v(oldFn) : _v();
				}
				else
				{
					_target[_k] = _v;
				}
			},
			_newslot = function( _k, _v )
			{
				_target[_k] <- _v;
			}
		});
		_fn(proxy);
	}

	::BalancedBackgrounds.hasMod <- function( _modID )
	{
		return ::mods_getRegisteredMod(_modID) != null;
	};

	::BalancedBackgrounds.hook <- function( _script, _fn )
	{
		::mods_hookExactClass(stripScriptsPrefix(_script), function( _o )
		{
			applyLegacyHook(_o, _fn);
		});
	};

	::BalancedBackgrounds.hookTree <- function( _script, _fn )
	{
		::mods_hookBaseClass(stripScriptsPrefix(_script), function( _o )
		{
			while (!("ClassName" in _o) && _o.SuperName != null)
			{
				_o = _o[_o.SuperName];
			}
			applyLegacyHook(_o, _fn);
		});
	};

	::mods_queue(::BalancedBackgrounds.ID, ">msu, >mod_modular_vanilla, >mod_dynamic_perks, >mod_reforged, >mod_hardened, >mod_backgrounds_and_events", loadModFiles);
}
