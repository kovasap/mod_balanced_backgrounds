#!/usr/bin/env python3
"""
simulate_bros.py - Generate and compare N random Battle Brothers recruits in Vanilla vs. Balanced Backgrounds.

Reads tunable constants directly from `mod_balanced_backgrounds/config/params.nut` and background
definitions from the local reference repositories (`Battle-Brothers-Scripts`, `mod-reforged`,
`Hardened`, `battle-brothers-xbe`). Edit `mod_balanced_backgrounds/config/params.nut` (or pass
`--set KEY=VALUE` on the command line) and re-run this script to iterate on mod balance.

Examples:
    ./simulate_bros.py beggar 8
    ./simulate_bros.py militia 8 --seed 42
    ./simulate_bros.py hedge_knight 8 --seed 42
    ./simulate_bros.py daytaler 6 --set VarianceLowbornMult=0.60 --set EndgameMeanSlope=0.15
    ./simulate_bros.py --list
"""

import argparse
import math
import os
import random
import re
import statistics
import sys

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
PARAMS_NUT_PATH = os.path.join(ROOT_DIR, "mod_balanced_backgrounds", "config", "params.nut")

ATTR_KEYS = [
    "Hitpoints",
    "Bravery",
    "Stamina",
    "Initiative",
    "MeleeSkill",
    "RangedSkill",
    "MeleeDefense",
    "RangedDefense",
]

# Const.Attributes enum order (index 2 is named Fatigue in Const.Attributes, Stamina on BaseProperties)
ENUM_NAMES = [
    "Hitpoints",
    "Bravery",
    "Fatigue",
    "Initiative",
    "MeleeSkill",
    "RangedSkill",
    "MeleeDefense",
    "RangedDefense",
]

SHORT_LABELS = {
    "Hitpoints": "HP",
    "Bravery": "Res",
    "Stamina": "Fat",
    "Initiative": "Ini",
    "MeleeSkill": "MAtk",
    "RangedSkill": "RAtk",
    "MeleeDefense": "MDef",
    "RangedDefense": "RDef",
}

BASE_HUMAN_RANGES = {
    "Hitpoints": [50, 60],
    "Bravery": [30, 40],
    "Stamina": [90, 100],
    "Initiative": [100, 110],
    "MeleeSkill": [47, 57],
    "RangedSkill": [32, 42],
    "MeleeDefense": [0, 5],
    "RangedDefense": [0, 5],
}
BASE_HUMAN_MID = {k: (v[0] + v[1]) * 0.5 for k, v in BASE_HUMAN_RANGES.items()}
BASE_HUMAN_HALF = {k: (v[1] - v[0]) * 0.5 for k, v in BASE_HUMAN_RANGES.items()}

# Const.AttributesLevelUp [Min, Max] for 0-star rolls
LEVELUP_BASE = [
    (2, 4),  # 0: Hitpoints
    (2, 4),  # 1: Bravery
    (2, 4),  # 2: Fatigue (Stamina)
    (3, 5),  # 3: Initiative
    (1, 3),  # 4: MeleeSkill
    (2, 4),  # 5: RangedSkill
    (1, 3),  # 6: MeleeDefense
    (2, 4),  # 7: RangedDefense
]

# Bytecode-verified fallback attributes for the 2 base Vanilla scripts whose decompiled .nut
# expressions were truncated in Battle-Brothers-Scripts.
BYTECODE_FALLBACK_ATTRS = {
    "executioner_background": {
        "id": "background.executioner",
        "name": "Executioner",
        "hiring_cost": 220,
        "daily_cost": 16,
        "excluded_talents": [5],  # RangedSkill
        "attrs": {
            "Hitpoints": [10, 7],
            "Bravery": [12, 10],
            "Stamina": [9, 14],
            "Initiative": [-5, -5],
            "MeleeSkill": [6, 8],
            "RangedSkill": [-5, 0],
            "MeleeDefense": [-5, 0],
            "RangedDefense": [-5, -5],
        },
    },
    "nomad_ranged_background": {
        "id": "background.nomad",
        "name": "Nomad",
        "hiring_cost": 200,
        "daily_cost": 15,
        "excluded_talents": [],
        "attrs": {
            "Hitpoints": [0, 0],
            "Bravery": [0, -3],
            "Stamina": [2, 0],
            "Initiative": [0, 0],
            "MeleeSkill": [5, 3],
            "RangedSkill": [15, 14],
            "MeleeDefense": [5, 3],
            "RangedDefense": [6, 5],
        },
    },
}

ENGLISH_NAME_OVERRIDES = {
    "paladin_background": "Oathtaker",
    "old_paladin_background": "Oathtaker (Old)",
    "slave_background": "Indebted",
    "slave_southern_background": "Indebted (Southern)",
    "slave_barbarian_background": "Indebted (Northern)",
    "beast_hunter_background": "Beast Slayer",
    "crucified_background": "Converted Crusader",
    "greenskin_goblin_background": "Goblin Slayer",
}

COMPANION_FIXED_TALENTS = {
    "companion_1h_background": {0: 2, 2: 1, 1: 1},
    "companion_1h_southern_background": {0: 2, 2: 1, 1: 1},
    "companion_2h_background": {4: 2, 6: 1, 1: 1},
    "companion_2h_southern_background": {4: 2, 6: 1, 1: 1},
    "companion_ranged_background": {5: 2, 7: 1, 3: 1},
    "companion_ranged_southern_background": {5: 2, 7: 1, 3: 1},
}


def round_int(x: float) -> int:
    return int(math.floor(x + 0.5)) if x >= 0.0 else -int(math.floor(-x + 0.5))


def strip_nut_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def parse_params_nut(path: str) -> dict:
    """Parse `::BalancedBackgrounds.Params <- { ... }` directly from Squirrel source."""
    with open(path, "r", encoding="utf-8") as f:
        clean = strip_nut_comments(f.read())

    m = re.search(r"::BalancedBackgrounds\.Params\s*<-\s*\{(.*)\}\s*;?\s*$", clean, flags=re.S)
    if not m:
        raise RuntimeError(f"Could not locate ::BalancedBackgrounds.Params table in {path}")
    body = m.group(1)

    params = {}
    # Parse nested 1-level tables first (e.g. SSPWeights = { ... }, MinAttributeFloor = { ... })
    for sub_m in re.finditer(r"(\w+)\s*=\s*\{([^}]*)\}", body):
        sub_name = sub_m.group(1)
        sub_body = sub_m.group(2)
        sub_dict = {}
        for kv in re.finditer(r"(\w+)\s*=\s*([^\s,}]+)", sub_body):
            sub_dict[kv.group(1)] = _parse_scalar(kv.group(2))
        params[sub_name] = sub_dict

    # Remove nested tables so top-level scalar regex doesn't re-match inner keys
    body_scalars = re.sub(r"\w+\s*=\s*\{[^}]*\}", "", body)
    for kv in re.finditer(r"(\w+)\s*=\s*(\"[^\"]*\"|true|false|-?\d+(?:\.\d+)?)", body_scalars):
        params[kv.group(1)] = _parse_scalar(kv.group(2))

    return params


def _parse_scalar(tok: str):
    tok = tok.strip().rstrip(",")
    if tok.startswith('"') and tok.endswith('"'):
        return tok[1:-1]
    if tok == "true":
        return True
    if tok == "false":
        return False
    if "." in tok:
        return float(tok)
    return int(tok)


def apply_cli_overrides(params: dict, overrides: list):
    for item in overrides or []:
        if "=" not in item:
            raise ValueError(f"Invalid --set override '{item}' (expected KEY=VALUE)")
        key, raw_val = item.split("=", 1)
        key = key.strip()
        val = _parse_scalar(f'"{raw_val}"' if not re.match(r'^(true|false|-?\d+(\.\d+)?|".*")$', raw_val.strip()) else raw_val.strip())
        if "." in key:
            outer, inner = key.split(".", 1)
            if outer not in params or not isinstance(params[outer], dict) or inner not in params[outer]:
                raise KeyError(f"Unknown nested parameter '{key}' in params.nut")
            params[outer][inner] = val
        else:
            if key not in params:
                raise KeyError(f"Unknown parameter '{key}' in params.nut (check spelling)")
            params[key] = val


def load_all_backgrounds() -> dict:
    """Discover and parse backgrounds from Vanilla, Reforged, and XBE reference directories."""
    raw_records = {}

    search_dirs = [
        ("Vanilla", os.path.join(ROOT_DIR, "Battle-Brothers-Scripts", "scripts", "skills", "backgrounds")),
        ("Reforged", os.path.join(ROOT_DIR, "mod-reforged", "scripts", "skills", "backgrounds")),
        ("XBE", os.path.join(ROOT_DIR, "battle-brothers-xbe", "scripts", "skills", "backgrounds", "hackflows")),
    ]

    for source_label, folder in search_dirs:
        if not os.path.isdir(folder):
            continue
        for fn in sorted(os.listdir(folder)):
            if not fn.endswith(".nut") or fn in ("character_background.nut", "character_backgrounds.nut"):
                continue
            stem = fn[:-4]
            full_path = os.path.join(folder, fn)
            with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                txt = strip_nut_comments(f.read())

            parent_m = re.search(r'inherit\(\s*"scripts/skills/backgrounds/([^"]+)"', txt)
            parent_stem = parent_m.group(1).split("/")[-1] if parent_m else None
            if parent_stem is None:
                # Decompiled southern variants call `this.<parent>.create()`
                super_m = re.search(r"this\.([a-z0-9_]+_background)\.create\(\)", txt)
                if super_m and super_m.group(1) != stem:
                    parent_stem = super_m.group(1)

            id_m = re.search(r'm\.ID\s*=\s*"([^"]+)"', txt)
            name_m = re.search(r'm\.Name\s*=\s*"([^"]+)"', txt)
            hc_m = re.search(r"m\.HiringCost\s*=\s*(-?\d+)", txt)
            dc_m = re.search(r"m\.DailyCost\s*=\s*(-?\d+)", txt)
            lvl_rand_m = re.search(r"m\.Level\s*=\s*(?:this\.)?(?:::)?Math\.rand\(\s*(\d+)\s*,\s*(\d+)\s*\)", txt)
            lvl_m = re.search(r"m\.Level\s*=\s*(\d+)", txt)
            untal_m = re.search(r"m\.IsUntalented\s*=\s*(true|false)", txt)

            excl = None
            excl_m = re.search(r"m\.ExcludedTalents\s*=\s*\[([^\]]*)\]", txt)
            if excl_m:
                excl = []
                for attr_m in re.finditer(r"Attributes\.(\w+)", excl_m.group(1)):
                    nm = attr_m.group(1)
                    if nm in ENUM_NAMES:
                        excl.append(ENUM_NAMES.index(nm))

            attrs = None
            if "function onChangeAttributes" in txt:
                attrs = {}
                for k in ATTR_KEYS:
                    am = re.search(rf"{k}\s*=\s*\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]", txt)
                    if am:
                        attrs[k] = [int(am.group(1)), int(am.group(2))]
                if len(attrs) != 8:
                    attrs = None

            level_range = None
            if lvl_rand_m:
                level_range = [int(lvl_rand_m.group(1)), int(lvl_rand_m.group(2))]
            elif lvl_m:
                level_range = [int(lvl_m.group(1)), int(lvl_m.group(1))]

            raw_records[stem] = {
                "stem": stem,
                "source": source_label,
                "parent": parent_stem if parent_stem != "character_background" else None,
                "id": id_m.group(1) if id_m else None,
                "raw_name": name_m.group(1) if name_m else None,
                "hiring_cost": int(hc_m.group(1)) if hc_m else None,
                "daily_cost": int(dc_m.group(1)) if dc_m else None,
                "level_range": level_range,
                "untalented": (untal_m.group(1) == "true") if untal_m else None,
                "excluded_talents": excl,
                "attrs": attrs,
            }

    # Resolve inheritance chains and bytecode fallbacks
    resolved = {}

    def resolve_one(stem: str) -> dict:
        if stem in resolved:
            return resolved[stem]
        rec = raw_records[stem]
        base = {
            "stem": stem,
            "source": rec["source"],
            "id": f"background.{stem.replace('_background', '')}",
            "name": None,
            "hiring_cost": 100,
            "daily_cost": 8,
            "level_range": [1, 1],
            "untalented": False,
            "excluded_talents": [],
            "attrs": {k: [0, 0] for k in ATTR_KEYS},
        }
        if rec["parent"] and rec["parent"] in raw_records:
            p_res = resolve_one(rec["parent"])
            base.update({
                "id": p_res["id"],
                "name": p_res["name"],
                "hiring_cost": p_res["hiring_cost"],
                "daily_cost": p_res["daily_cost"],
                "level_range": list(p_res["level_range"]),
                "untalented": p_res["untalented"],
                "excluded_talents": list(p_res["excluded_talents"]),
                "attrs": {k: list(v) for k, v in p_res["attrs"].items()},
            })

        if stem in BYTECODE_FALLBACK_ATTRS:
            fb = BYTECODE_FALLBACK_ATTRS[stem]
            base["id"] = fb["id"]
            base["name"] = fb["name"]
            base["hiring_cost"] = fb["hiring_cost"]
            base["daily_cost"] = fb["daily_cost"]
            if rec["level_range"] is not None:
                base["level_range"] = list(rec["level_range"])
            base["excluded_talents"] = list(fb["excluded_talents"])
            base["attrs"] = {k: list(v) for k, v in fb["attrs"].items()}
        else:
            if rec["id"] is not None:
                base["id"] = rec["id"]
            if rec["raw_name"] is not None and all(ord(c) < 128 for c in rec["raw_name"]):
                base["name"] = rec["raw_name"]
            if rec["hiring_cost"] is not None:
                base["hiring_cost"] = rec["hiring_cost"]
            if rec["daily_cost"] is not None:
                base["daily_cost"] = rec["daily_cost"]
            if rec["level_range"] is not None:
                base["level_range"] = list(rec["level_range"])
            if rec["untalented"] is not None:
                base["untalented"] = rec["untalented"]
            if rec["excluded_talents"] is not None:
                base["excluded_talents"] = list(rec["excluded_talents"])
            if rec["attrs"] is not None:
                base["attrs"] = {k: list(v) for k, v in rec["attrs"].items()}

        if stem in ENGLISH_NAME_OVERRIDES:
            base["name"] = ENGLISH_NAME_OVERRIDES[stem]
        elif not base["name"]:
            pretty = stem.replace("_background", "").replace("rf_", "").replace("_", " ").title()
            base["name"] = pretty

        resolved[stem] = base
        return base

    for st in raw_records:
        resolve_one(st)

    return resolved


class BalancedBackgroundsModel:
    """Exact Python mirror of `mod_balanced_backgrounds/config/balance_math.nut`."""

    def __init__(self, params: dict, backgrounds: dict):
        self.p = params
        self.backgrounds = backgrounds
        self.pool_curve_cache = {}
        self.target_anchor = None

    def compute_ssp_from_deltas(self, d: dict) -> float:
        p = self.p
        weights = p["SSPWeights"]
        is_ded_ranged = d["RangedSkill"] >= 10.0 and d["MeleeSkill"] <= 0.0
        is_glass_archer = d["RangedSkill"] >= 20.0 and d["MeleeSkill"] < 0.0
        tot = 0.0
        for k in ATTR_KEYS:
            val = float(d[k])
            w = float(weights[k])
            if val < 0.0:
                if k in ("Initiative", "RangedDefense"):
                    val *= p["SecondaryNegDiscount"]
                elif k == "RangedSkill" and d["MeleeSkill"] >= 5.0:
                    val *= p["OffRoleAttackNegDiscount"]
                elif k in ("MeleeSkill", "MeleeDefense") and is_ded_ranged:
                    val *= p["OffRoleAttackNegDiscount"]
                elif k in ("Hitpoints", "Stamina") and is_glass_archer:
                    val *= p["GlassArcherBodyNegDiscount"]
            tot += val * w
        pos_m = max(0.0, d["MeleeSkill"] * weights["MeleeSkill"])
        pos_r = max(0.0, d["RangedSkill"] * weights["RangedSkill"])
        if pos_m > 0.0 and pos_r > 0.0:
            tot -= p["DualOffenseDiscount"] * min(pos_m, pos_r)
        return tot

    def compute_ssp_from_ranges(self, attrs: dict) -> float:
        return self.compute_ssp_from_deltas({k: (attrs[k][0] + attrs[k][1]) * 0.5 for k in ATTR_KEYS})

    def compute_actor_ssp(self, props: dict) -> float:
        return self.compute_ssp_from_deltas({k: props[k] - BASE_HUMAN_MID[k] for k in ATTR_KEYS})

    def filter_excluded_talents(self, bg_id: str, excluded: list) -> list:
        if not excluded:
            return []
        if not self.p["FilterExcludedTalents"]:
            return list(excluded)
        if bg_id == "background.deserter" and 1 in excluded:
            return [1]
        if bg_id == "background.cripple" and 3 in excluded:
            return [3]
        if bg_id == "background.hackflows_leper" and 0 in excluded:
            return [0]
        for attr_idx in excluded:
            if attr_idx in (4, 5):  # MeleeSkill or RangedSkill
                return [attr_idx]
        return []

    def compute_variance_mult(self, s_mid: float) -> float:
        p = self.p
        span = p["VarianceAnchorHighSSP"] - p["VarianceAnchorLowSSP"]
        t = max(0.0, min(1.0, (s_mid - p["VarianceAnchorLowSSP"]) / span)) if span > 0 else 0.5
        exp = p["VarianceCurveExponent"]
        if exp != 1.0 and 0.0 < t < 1.0:
            t = t ** exp
        return p["VarianceLowbornMult"] + t * (p["VarianceHighbornMult"] - p["VarianceLowbornMult"])

    def transform_attribute_ranges(self, raw_attrs: dict) -> tuple:
        p = self.p
        s0 = self.compute_ssp_from_ranges(raw_attrs)
        comp_attrs = raw_attrs

        if p["EnableOutlierCompression"] and (s0 < p["LowOutlierThresholdSSP"] or s0 > p["HighOutlierThresholdSSP"]):
            scale_pos = s0 > p["HighOutlierThresholdSSP"]
            s_target = (
                min(p["HighOutlierCeilingSSP"], p["HighOutlierThresholdSSP"] + p["HighOutlierSlope"] * (s0 - p["HighOutlierThresholdSSP"]))
                if scale_pos
                else max(p["LowOutlierFloorSSP"], p["LowOutlierThresholdSSP"] + p["LowOutlierSlope"] * (s0 - p["LowOutlierThresholdSSP"]))
            )
            best_err = 999999.0
            for step in range(10, 101):
                alpha = step * 0.01
                cand = {}
                for k in ATTR_KEYS:
                    v = raw_attrs[k]
                    if scale_pos:
                        cand[k] = [round_int(v[0] * alpha) if v[0] > 0 else v[0], round_int(v[1] * alpha) if v[1] > 0 else v[1]]
                    else:
                        cand[k] = [round_int(v[0] * alpha) if v[0] < 0 else v[0], round_int(v[1] * alpha) if v[1] < 0 else v[1]]
                err = abs(self.compute_ssp_from_ranges(cand) - s_target)
                if err < best_err:
                    best_err = err
                    comp_attrs = cand

        s_mid = self.compute_ssp_from_ranges(comp_attrs)
        var_mult = self.compute_variance_mult(s_mid)
        out = {}

        for k in ATTR_KEYS:
            mid_delta = (comp_attrs[k][0] + comp_attrs[k][1]) * 0.5
            base_range = BASE_HUMAN_RANGES[k]
            base_half = BASE_HUMAN_HALF[k]
            target_half = base_half * var_mult

            if k == "MeleeSkill" and raw_attrs["MeleeSkill"][0] < 8 and round_int(mid_delta - target_half + base_half) >= 8:
                target_half = max(target_half, mid_delta - 2.0)

            c0 = round_int(mid_delta - target_half + base_half)
            c1 = round_int(mid_delta + target_half - base_half)
            floor_val = p["MinAttributeFloor"][k]

            if base_range[0] + c0 < floor_val:
                c0 = floor_val - base_range[0]
            if base_range[0] + c0 > base_range[1] + c1:
                fixed_val = max(floor_val, round_int(BASE_HUMAN_MID[k] + mid_delta))
                c0 = fixed_val - base_range[0]
                c1 = fixed_val - base_range[1]
            out[k] = [c0, c1]

        return out, var_mult

    def params_from_u(self, u: float, max_n: int) -> tuple:
        p = self.p
        u = max(0.0, min(1.0, u))
        anchor_u = max(0.05, min(0.95, p["TargetAnchorU"]))

        if u <= anchor_u:
            t = u / anchor_u
            mu_n = p["HighbornMeanTalents"] + t * (p["TargetMeanTalents"] - p["HighbornMeanTalents"])
            p1 = p["HighbornStar1Pct"] + t * (p["TargetStar1Pct"] - p["HighbornStar1Pct"])
            p2 = p["HighbornStar2Pct"] + t * (p["TargetStar2Pct"] - p["HighbornStar2Pct"])
        else:
            t = (u - anchor_u) / (1.0 - anchor_u)
            mu_n = p["TargetMeanTalents"] + t * (p["LowbornMeanTalents"] - p["TargetMeanTalents"])
            p1 = p["TargetStar1Pct"] + t * (p["LowbornStar1Pct"] - p["TargetStar1Pct"])
            p2 = p["TargetStar2Pct"] + t * (p["LowbornStar2Pct"] - p["TargetStar2Pct"])

        sigma_n = max(0.08, p["StarCountSigmaHighborn"] + u * (p["StarCountSigmaLowborn"] - p["StarCountSigmaHighborn"]))
        raw_w = [math.exp(-0.5 * ((c - mu_n) / sigma_n) ** 2) for c in range(max_n + 1)]
        raw_sum = sum(raw_w)

        cw = [[c, round_int(100.0 * raw_w[c] / raw_sum)] for c in range(max_n + 1) if raw_sum > 0 and round_int(100.0 * raw_w[c] / raw_sum) > 0]
        if not cw:
            cw = [[0, 100]]
        diff = 100 - sum(w for _, w in cw)
        if diff != 0:
            best = max(range(len(cw)), key=lambda i: cw[i][1])
            cw[best][1] += diff

        tw1 = max(0, min(100, round_int(p1)))
        tw2 = max(0, min(100 - tw1, round_int(p2)))
        tw3 = max(0, 100 - tw1 - tw2)
        return cw, [tw1, tw2, tw3]

    def compute_exact_g_top3_at_u(self, open_attrs: list, u: float) -> float:
        m = len(open_attrs)
        if m == 0:
            return 0.0
        max_n = max(0, m - 1) if self.p["LeaveAtLeastOneUntalentedAttr"] else m
        cw, tw = self.params_from_u(u, max_n)
        tiers = [(s, w * 0.01) for s, w in ((1, tw[0]), (2, tw[1]), (3, tw[2])) if w > 0]
        if not tiers:
            return 0.0

        quant_gains = [max(0, min(330, round_int(20.0 * self.p["SSPWeights"][ATTR_KEYS[idx]]))) for idx in open_attrs]
        states = [{0: 1.0}] + [{} for _ in range(m)]
        for idx, w in enumerate(quant_gains):
            for c in range(idx, -1, -1):
                src = states[c]
                if not src:
                    continue
                dst = states[c + 1]
                for packed, ps in src.items():
                    a = packed // 1000000
                    b = (packed // 1000) % 1000
                    d = packed % 1000
                    for s, pt in tiers:
                        g = s * w
                        if g >= a:
                            nk = g * 1000000 + a * 1000 + b
                        elif g >= b:
                            nk = a * 1000000 + g * 1000 + b
                        elif g >= d:
                            nk = a * 1000000 + b * 1000 + g
                        else:
                            nk = packed
                        dst[nk] = dst.get(nk, 0.0) + ps * pt

        ev_by_cnt = [0.0] * (m + 1)
        for c in range(1, max_n + 1):
            tot = 0.0
            for packed, ps in states[c].items():
                q_sum = (packed // 1000000) + ((packed // 1000) % 1000) + (packed % 1000)
                tot += (q_sum * 0.25) * ps
            ev_by_cnt[c] = tot / math.comb(m, c)

        return sum((w * 0.01) * ev_by_cnt[cnt] for cnt, w in cw if 0 < cnt <= max_n)

    def get_pool_curve(self, open_attrs: list) -> list:
        key = tuple(open_attrs)
        if key in self.pool_curve_cache:
            return self.pool_curve_cache[key]
        table = [0.0] * 101
        for even in range(0, 101, 2):
            table[even] = self.compute_exact_g_top3_at_u(open_attrs, even * 0.01)
        for odd in range(1, 100, 2):
            table[odd] = 0.5 * (table[odd - 1] + table[odd + 1])
        self.pool_curve_cache[key] = table
        return table

    def get_target_anchor(self) -> tuple:
        if self.target_anchor is not None:
            return self.target_anchor
        target_stem = self.p["TargetBackground"].split("/")[-1].replace(".nut", "")
        if target_stem in self.backgrounds:
            tbg = self.backgrounds[target_stem]
            start_ssp = self.compute_ssp_from_ranges(tbg["attrs"])
            excl = self.filter_excluded_talents(tbg["id"], tbg["excluded_talents"])
            open_attrs = [i for i in range(8) if i not in excl]
        else:
            start_ssp = 23.30
            open_attrs = list(range(8))
        anchor_step = max(0, min(100, round_int(self.p["TargetAnchorU"] * 100.0)))
        endgame_ssp = start_ssp + self.get_pool_curve(open_attrs)[anchor_step] + self.p["TargetBackgroundBonusSSP"]
        self.target_anchor = (start_ssp, endgame_ssp)
        return self.target_anchor

    def get_star_profile(self, bg: dict) -> dict:
        mod_attrs, var_mult = self.transform_attribute_ranges(bg["attrs"])
        s_adj = self.compute_ssp_from_ranges(mod_attrs)
        excl = self.filter_excluded_talents(bg["id"], bg["excluded_talents"])
        open_attrs = [i for i in range(8) if i not in excl]
        max_n = max(0, len(open_attrs) - 1) if self.p["LeaveAtLeastOneUntalentedAttr"] else len(open_attrs)

        start_anchor, end_anchor = self.get_target_anchor()
        target_e11 = end_anchor + self.p["EndgameMeanSlope"] * (s_adj - start_anchor)
        desired_gain = target_e11 - s_adj

        curve = self.get_pool_curve(open_attrs)
        best_step = min(range(101), key=lambda st: abs(curve[st] - desired_gain))
        cw, tw = self.params_from_u(best_step * 0.01, max_n)
        return {
            "u": best_step * 0.01,
            "s_adj": s_adj,
            "var_mult": var_mult,
            "mod_attrs": mod_attrs,
            "excluded": excl,
            "open_attrs": open_attrs,
            "count_weights": cw,
            "tier_weights": tw,
        }

    def roll_starting_level(self, bg: dict, s_adj: float, rng: random.Random) -> int:
        p = self.p
        van_lvl = rng.randint(bg["level_range"][0], bg["level_range"][1])
        if not p["EnableHighbornPendingLevels"]:
            return van_lvl
        if bg["id"] == "background.companion" or bg["level_range"][0] >= 8:
            return van_lvl
        if s_adj < p["HighbornPendingLevelMinSSP"]:
            return van_lvl

        min_p = max(1, min(6, int(p["HighbornMinPendingLevels"])))
        max_p = max(min_p, min(6, int(p["HighbornMaxPendingLevels"])))
        raw_weights = [
            max(0, int(p["PendingLevelWeight1"])),
            max(0, int(p["PendingLevelWeight2"])),
            max(0, int(p["PendingLevelWeight3"])),
            max(0, int(p["PendingLevelWeight4"])),
            max(0, int(p["PendingLevelWeight5"])),
            max(0, int(p["PendingLevelWeight6"])),
        ]
        tot_w = sum(raw_weights[n - 1] for n in range(min_p, max_p + 1))
        if tot_w <= 0:
            return 1 + min_p
        r = rng.randint(1, tot_w)
        cum = 0
        for n in range(min_p, max_p + 1):
            cum += raw_weights[n - 1]
            if r <= cum:
                return 1 + n
        return 1 + max_p

    def calc_stat_wage(self, props: dict) -> int:
        b_ssp = self.compute_actor_ssp(props)
        return max(self.p["MinDailyWage"], round_int(self.p["DailyWageBase"] + self.p["DailyWagePerSSP"] * b_ssp))

    def calc_base_hiring_cost(self, props: dict, level: int = 1) -> int:
        b_ssp = self.compute_actor_ssp(props)
        pending = max(0, level - 1)
        lvl1_cost = max(20.0, self.p["HiringCostBaseMult"] * 10.0 * math.exp(self.p["HiringCostExpSlope"] * b_ssp))
        pending_cost = math.floor(self.p["PendingLevelCostMult"] * (pending ** self.p["PendingLevelCostExp"])) if pending > 0 else 0.0
        return 10 * int(math.ceil((lvl1_cost + pending_cost) * 0.1))


def simulate_level_ups(base_props: dict, talents: list, ssp_weights: dict, rng: random.Random) -> tuple:
    """Roll 10 real Battle Brothers level-ups and invest in the brother's top 3 SSP-gain attributes."""
    gains_10 = [0] * 8
    for idx in range(8):
        lo, hi = LEVELUP_BASE[idx]
        t = talents[idx]
        r_lo = lo + (2 if t == 3 else t)
        r_hi = hi + (1 if t == 3 else 0)
        gains_10[idx] = sum(rng.randint(r_lo, r_hi) for _ in range(10))

    # Pick the 3 attributes that maximize the brother's effective combat build at Level 11:
    # choose best offensive skill (MeleeSkill vs RangedSkill) + top 2 remaining SSP contributors.
    m_proj = (base_props["MeleeSkill"] + gains_10[4] - BASE_HUMAN_MID["MeleeSkill"]) * ssp_weights["MeleeSkill"]
    r_proj = (base_props["RangedSkill"] + gains_10[5] - BASE_HUMAN_MID["RangedSkill"]) * ssp_weights["RangedSkill"]
    primary_atk = 4 if m_proj >= r_proj else 5
    secondary_atk = 5 if primary_atk == 4 else 4

    scored_others = []
    for idx in range(8):
        if idx in (primary_atk, secondary_atk):
            continue
        k = ATTR_KEYS[idx]
        # Score by star gain + role importance so standard builds invest realistically
        score = gains_10[idx] * ssp_weights[k] + (8.0 if idx == 6 and primary_atk == 4 else 0.0)
        scored_others.append((score, idx))
    scored_others.sort(reverse=True)
    chosen_3 = {primary_atk, scored_others[0][1], scored_others[1][1]}

    lvl11_if_always_chosen = {ATTR_KEYS[idx]: base_props[ATTR_KEYS[idx]] + gains_10[idx] for idx in range(8)}
    lvl11_build_props = dict(base_props)
    for idx in chosen_3:
        lvl11_build_props[ATTR_KEYS[idx]] += gains_10[idx]
    return lvl11_if_always_chosen, lvl11_build_props, chosen_3


def generate_vanilla_bro(bg: dict, model: BalancedBackgroundsModel, rng: random.Random) -> dict:
    props = {}
    for k in ATTR_KEYS:
        lo = BASE_HUMAN_RANGES[k][0] + bg["attrs"][k][0]
        hi = BASE_HUMAN_RANGES[k][1] + bg["attrs"][k][1]
        if lo > hi:
            lo, hi = hi, lo
        props[k] = rng.randint(lo, hi)

    talents = [0] * 8
    if bg["stem"] in COMPANION_FIXED_TALENTS:
        for idx, st in COMPANION_FIXED_TALENTS[bg["stem"]].items():
            talents[idx] = st
    elif not bg["untalented"]:
        open_pool = [i for i in range(8) if i not in bg["excluded_talents"]]
        rng.shuffle(open_pool)
        for idx in open_pool[: min(3, len(open_pool))]:
            r = rng.randint(1, 100)
            talents[idx] = 1 if r <= 60 else (2 if r <= 90 else 3)

    s1 = model.compute_actor_ssp(props)
    star_gains = sorted([talents[i] * 5.0 * model.p["SSPWeights"][ATTR_KEYS[i]] for i in range(8)], reverse=True)
    e11_ssp = s1 + sum(star_gains[:3])
    lvl11_all, _, chosen_3 = simulate_level_ups(props, talents, model.p["SSPWeights"], rng)

    # Vanilla hiring cost (before equipment) and daily wage
    lvl = rng.randint(bg["level_range"][0], bg["level_range"][1])
    base_hire = int(math.ceil((math.floor(bg["hiring_cost"] + 500.0 * ((lvl - 1) ** 1.5))) * 0.1)) * 10
    dc_base = (bg["daily_cost"] + 1) if bg["daily_cost"] > 0 else 0
    mult = rng.randint(90, 110) * 0.01
    wage_l1 = round_int(dc_base * mult * (1.1 ** (lvl - 1)))
    wage_l11 = round_int(dc_base * mult * (1.1 ** 10))

    return {
        "level": lvl,
        "props_l1": props,
        "props_l11_all": lvl11_all,
        "chosen_3": chosen_3,
        "talents": talents,
        "s1_ssp": s1,
        "e11_ssp": e11_ssp,
        "base_hire": base_hire,
        "wage_l1": wage_l1,
        "wage_l11": wage_l11,
    }


def generate_mod_bro(bg: dict, profile: dict, model: BalancedBackgroundsModel, rng: random.Random) -> dict:
    mod_attrs = profile["mod_attrs"]
    props = {}
    for k in ATTR_KEYS:
        lo = BASE_HUMAN_RANGES[k][0] + mod_attrs[k][0]
        hi = BASE_HUMAN_RANGES[k][1] + mod_attrs[k][1]
        props[k] = rng.randint(lo, hi)

    talents = [0] * 8
    is_untalented = bg["untalented"] and (bg["stem"] not in COMPANION_FIXED_TALENTS)
    if not is_untalented and profile["open_attrs"]:
        cw = profile["count_weights"]
        tw = profile["tier_weights"]
        r_cnt = rng.randint(1, 100)
        cum = 0
        chosen_n = cw[-1][0]
        for cnt, w in cw:
            cum += w
            if r_cnt <= cum:
                chosen_n = cnt
                break
        open_pool = list(profile["open_attrs"])
        rng.shuffle(open_pool)
        for idx in open_pool[:chosen_n]:
            r_st = rng.randint(1, 100)
            talents[idx] = 1 if r_st <= tw[0] else (2 if r_st <= tw[0] + tw[1] else 3)

    s1 = model.compute_actor_ssp(props)
    star_gains = sorted([talents[i] * 5.0 * model.p["SSPWeights"][ATTR_KEYS[i]] for i in range(8)], reverse=True)
    e11_ssp = s1 + sum(star_gains[:3])
    lvl11_all, lvl11_build, chosen_3 = simulate_level_ups(props, talents, model.p["SSPWeights"], rng)

    lvl = model.roll_starting_level(bg, profile["s_adj"], rng)
    base_hire = model.calc_base_hiring_cost(props, lvl)
    wage_l1 = model.calc_stat_wage(props)
    wage_l11 = model.calc_stat_wage(lvl11_build)

    return {
        "level": lvl,
        "props_l1": props,
        "props_l11_all": lvl11_all,
        "chosen_3": chosen_3,
        "talents": talents,
        "s1_ssp": s1,
        "e11_ssp": e11_ssp,
        "base_hire": base_hire,
        "wage_l1": wage_l1,
        "wage_l11": wage_l11,
    }


def format_stat_cell(bro: dict, attr_idx: int) -> str:
    k = ATTR_KEYS[attr_idx]
    v1 = bro["props_l1"][k]
    v11 = bro["props_l11_all"][k]
    st = "*" * bro["talents"][attr_idx]
    return f"{v1:3d}{st:<3s}->{v11:<3d}"


def print_bro_table(title: str, bros: list):
    print(f"\n=== {title} ===")
    cols = ["HP", "Fat", "Res", "Ini", "MAtk", "MDef", "RAtk", "RDef"]
    col_order = [0, 2, 1, 3, 4, 6, 5, 7]
    hdr_stats = " ".join(f"{c:^11s}" for c in cols)
    print(f"{'#':>2s} | {'Start':>6s} | {hdr_stats} | {'Stars':>5s} | {'L1 SSP':>6s} | {'L11 SSP':>7s} | {'NoGear':>6s} | {'Wage':>8s}")
    print("-" * 153)
    for idx, b in enumerate(bros, 1):
        cells = " ".join(format_stat_cell(b, a_idx) for a_idx in col_order)
        tot_stars = sum(b["talents"])
        pend = b["level"] - 1
        lvl_str = f"L{b['level']}(+{pend})"
        wage_str = f"{b['wage_l1']:>2d}->{b['wage_l11']:<2d}/d"
        print(
            f"{idx:2d} | {lvl_str:>6s} | {cells} | {tot_stars:4d}* | {b['s1_ssp']:+6.1f} | {b['e11_ssp']:7.1f} | {b['base_hire']:5d}c | {wage_str:>8s}"
        )


def resolve_background_query(query: str, backgrounds: dict) -> dict:
    q = query.strip().lower().replace(".nut", "").replace(" ", "_")
    for candidate in (q, f"{q}_background", f"rf_{q}_background"):
        if candidate in backgrounds:
            return backgrounds[candidate]
    matches = [
        b for stem, b in backgrounds.items()
        if q in stem.lower() or q in b["name"].lower().replace(" ", "_") or q in b["id"].lower()
    ]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        exact_name = [b for b in matches if b["name"].lower().replace(" ", "_") == q]
        if len(exact_name) == 1:
            return exact_name[0]
        names = ", ".join(sorted(b["stem"] for b in matches[:10]))
        raise SystemExit(f"Ambiguous background '{query}'. Matches: {names}")
    raise SystemExit(f"Background '{query}' not found. Run `./simulate_bros.py --list` to see all backgrounds.")


def summarize_samples(vals: list) -> str:
    s = sorted(vals)
    n = len(s)
    return (
        f"Mean {statistics.mean(s):5.1f} | SD {statistics.stdev(s):4.1f} | "
        f"P10 {s[int(0.10 * n)]:5.1f} | P50 {s[int(0.50 * n)]:5.1f} | "
        f"P90 {s[int(0.90 * n)]:5.1f} | P95 {s[int(0.95 * n)]:5.1f} | P99 {s[int(0.99 * n)]:5.1f}"
    )


def main():
    parser = argparse.ArgumentParser(
        description="Simulate N random recruits of a Battle Brothers background in Vanilla vs. Balanced Backgrounds."
    )
    parser.add_argument("background", nargs="?", help="Background name or script (e.g. beggar, militia, hedge_knight)")
    parser.add_argument("count", nargs="?", type=int, default=8, help="Number of recruits to generate (default: 8)")
    parser.add_argument("-l", "--list", action="store_true", help="List all available backgrounds and exit")
    parser.add_argument("-s", "--seed", type=int, default=None, help="Random seed for reproducible rolls")
    parser.add_argument(
        "-p", "--set", action="append", default=[], metavar="KEY=VALUE",
        help="Override any constant from config/params.nut (repeatable, e.g. -p VarianceLowbornMult=2.6)"
    )
    parser.add_argument(
        "-c", "--compare", default=None, metavar="OTHER_BG",
        help="Benchmark background for Level-11 win-rate comparison (default: hedge_knight or daytaler)"
    )
    parser.add_argument("--trials", type=int, default=3000, help="Monte Carlo sample size for distribution summary")
    args = parser.parse_args()

    params = parse_params_nut(PARAMS_NUT_PATH)
    apply_cli_overrides(params, args.set)
    backgrounds = load_all_backgrounds()
    model = BalancedBackgroundsModel(params, backgrounds)

    if args.list:
        start_anchor, end_anchor = model.get_target_anchor()
        print(f"Target Anchor: {params['TargetBackground']} (StartSSP={start_anchor:+.1f}, EndgameSSP={endgame_ssp_fmt(end_anchor)})")
        print(f"{'Script Stem':38s} | {'Src':8s} | {'Name':24s} | {'Orig S0':>7s} | {'Adj S':>7s} | {'VarMult':>7s} | {'u':>4s}")
        print("-" * 112)
        rows = sorted(backgrounds.values(), key=lambda b: (model.compute_ssp_from_ranges(b["attrs"]), b["stem"]))
        for b in rows:
            s0 = model.compute_ssp_from_ranges(b["attrs"])
            prof = model.get_star_profile(b)
            print(
                f"{b['stem']:38s} | {b['source']:8s} | {b['name'][:24]:24s} | "
                f"{s0:+7.1f} | {prof['s_adj']:+7.1f} | {prof['var_mult']:6.2f}x | {prof['u']:4.2f}"
            )
        return

    if not args.background:
        parser.print_help()
        sys.exit(1)

    bg = resolve_background_query(args.background, backgrounds)
    profile = model.get_star_profile(bg)
    start_anchor, end_anchor = model.get_target_anchor()

    seed = args.seed if args.seed is not None else random.randrange(1, 1_000_000)
    rng_van = random.Random(seed)
    rng_mod = random.Random(seed)

    van_bros = [generate_vanilla_bro(bg, model, rng_van) for _ in range(args.count)]
    mod_bros = [generate_mod_bro(bg, profile, model, rng_mod) for _ in range(args.count)]

    van_excl = ", ".join(SHORT_LABELS[ATTR_KEYS[i]] for i in bg["excluded_talents"]) or "None"
    mod_excl = ", ".join(SHORT_LABELS[ATTR_KEYS[i]] for i in profile["excluded"]) or "None"
    cw_str = " / ".join(f"{c}({w}%)" for c, w in profile["count_weights"])
    tw = profile["tier_weights"]

    print("=" * 144)
    print(f"Background : {bg['name']} ({bg['stem']}.nut, {bg['source']})  |  Seed: {seed}")
    print(
        f"Mod Params : TargetBackground={params['TargetBackground']} (S0={start_anchor:+.1f}, E11={end_anchor:.1f}) | "
        f"EndgameMeanSlope={params['EndgameMeanSlope']:+.2f} | "
        f"VarMult=[{params['VarianceHighbornMult']:.2f}x..{params['VarianceLowbornMult']:.2f}x]"
    )
    print(
        f"Calibration: Orig S0={model.compute_ssp_from_ranges(bg['attrs']):+.1f} -> Adj S={profile['s_adj']:+.1f} | "
        f"Roll Width={profile['var_mult']:.2f}x | ExcludedTalents: Vanilla [{van_excl}] -> Mod [{mod_excl}]"
    )
    print(f"Star Curve : u={profile['u']:.2f} | Count Weights: {cw_str} | Star Tiers (1*/2*/3*): {tw[0]}% / {tw[1]}% / {tw[2]}%")
    print("Note       : Every stat cell shows `L1Base + Stars -> Lvl11` (projected Level-11 value if chosen on every level-up).")
    print("=" * 144)

    print_bro_table(f"VANILLA ({args.count} Recruits)", van_bros)
    print_bro_table(f"BALANCED BACKGROUNDS ({args.count} Recruits)", mod_bros)

    # Monte Carlo distribution & matchup summary
    mc_rng_v = random.Random(seed + 10000)
    mc_rng_m = random.Random(seed + 10000)
    van_mc = [generate_vanilla_bro(bg, model, mc_rng_v)["e11_ssp"] for _ in range(args.trials)]
    mod_mc = [generate_mod_bro(bg, profile, model, mc_rng_m)["e11_ssp"] for _ in range(args.trials)]

    cmp_query = args.compare or ("hedge_knight_background" if profile["s_adj"] <= start_anchor else "daytaler_background")
    cmp_bg = resolve_background_query(cmp_query, backgrounds)
    cmp_prof = model.get_star_profile(cmp_bg)
    van_cmp_mc = [generate_vanilla_bro(cmp_bg, model, mc_rng_v)["e11_ssp"] for _ in range(args.trials)]
    mod_cmp_mc = [generate_mod_bro(cmp_bg, cmp_prof, model, mc_rng_m)["e11_ssp"] for _ in range(args.trials)]

    van_diffs = sorted([a - b_val for a, b_val in zip(van_mc, van_cmp_mc)])
    mod_diffs = sorted([a - b_val for a, b_val in zip(mod_mc, mod_cmp_mc)])
    van_wins = [d for d in van_diffs if d > 0]
    mod_wins = [d for d in mod_diffs if d > 0]

    van_win = len(van_wins) * 100.0 / args.trials
    mod_win = len(mod_wins) * 100.0 / args.trials
    mod_avg_win = statistics.mean(mod_wins) if mod_wins else 0.0
    mod_p99_diff = mod_diffs[int(0.99 * args.trials)]

    print("\n" + "=" * 153)
    print(f"LEVEL-11 ENDGAME SSP DISTRIBUTION ({args.trials} Simulated Recruits)")
    print(f"  Vanilla              : {summarize_samples(van_mc)}")
    print(f"  Balanced Backgrounds : {summarize_samples(mod_mc)}")
    print(
        f"  Matchup vs {cmp_bg['name']} ({cmp_bg['stem']}) at Level 11: "
        f"Vanilla Win = {van_win:5.1f}% -> Mod Win = {mod_win:5.1f}% "
        f"(Avg Win Margin: {mod_avg_win:+.1f} SSP | 1% P99 Diff: {mod_p99_diff:+.1f} SSP)"
    )
    print("=" * 153)


def endgame_ssp_fmt(v: float) -> str:
    return f"{v:.1f}"


if __name__ == "__main__":
    main()
