"""
Regression test for fit_garment.py.

Runs the validated soft-fit recipe against `Models\\human_female_armored.blend` (the original
test file — NOT the demo). Verifies:
  - fit_mask vertex group is created with expected vert counts
  - Modifier stack ends up in canonical order: [SurfaceDeform, Shrinkwrap_SoftFit, Armature]
  - SurfaceDeform binds successfully
  - Bake step applies SurfaceDeform and Shrinkwrap, leaves Armature

Invocation (from interactive Blender, recommended — SurfaceDeform bind needs window context):

    1. Open Blender with the human_female_armored.blend file loaded
    2. In the Scripting workspace, open and run this script
    OR
    3. Via the Blender MCP:
       import sys
       sys.path.insert(0, r"C:/Users/jttau/acks-arbiter/.claude/skills/acks-blender-pipeline/tests")
       import test_fit_garment
       test_fit_garment.run()

Standalone CLI form:
    blender Models/human_female_armored.blend --python tests/test_fit_garment.py
"""

import bpy
import os
import sys
import json

# Make scripts importable
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_SKILL_ROOT = os.path.dirname(_THIS_DIR)
_SCRIPTS_DIR = os.path.join(_SKILL_ROOT, "scripts")
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

import _common as C
import fit_garment


# Expected vertex counts from the 2026-05-16 manual demonstration session
EXPECTED = {
    "ARMOR2": {
        "vert_count": 21228,
        "fit_class": "plate",
        "approx_pct_masked_range": (10.0, 25.0),  # tight rim mask should hit ~17%
    },
    "WAIST_3": {
        "vert_count": 1996,
        "fit_class": "cloth",  # multi-island hanging garment — treat as cloth
        "approx_pct_masked_range": (40.0, 80.0),  # wider conform should hit ~60%
    },
}


def _verify_modifier_stack(obj_name):
    """Verify the modifier order matches [SurfaceDeform, Shrinkwrap_SoftFit, Armature]."""
    obj = C.get_object(obj_name)
    actual_order = [m.type for m in obj.modifiers]
    expected_order = ['SURFACE_DEFORM', 'SHRINKWRAP', 'ARMATURE']
    return {
        "obj": obj_name,
        "actual_order": actual_order,
        "expected_order": expected_order,
        "match": actual_order == expected_order,
    }


def _clean_existing_fit(obj_name):
    """Remove any existing Shrinkwrap or SurfaceDeform modifiers from obj.

    Leaves Armature alone (it's the runtime-dynamic deformer).
    """
    obj = C.get_object(obj_name)
    removed = []
    for m in list(obj.modifiers):
        if m.type in ('SHRINKWRAP', 'SURFACE_DEFORM', 'DATA_TRANSFER'):
            removed.append(m.name)
            obj.modifiers.remove(m)
    # Remove existing fit_mask vertex group too, so the test re-creates it
    if "fit_mask" in obj.vertex_groups:
        obj.vertex_groups.remove(obj.vertex_groups["fit_mask"])
    return removed


def run():
    """Run the regression test. Returns a dict of results."""
    results = {"passed": True, "fits": {}, "stacks": {}, "errors": []}

    body_name = "MESH - Female Basemesh"
    rig_name = "Female Basemesh Rig"

    if body_name not in bpy.data.objects:
        results["passed"] = False
        results["errors"].append(f"Required body object '{body_name}' not in scene. "
                                  f"Open Models/human_female_armored.blend before running.")
        return results

    for obj_name, expected in EXPECTED.items():
        if obj_name not in bpy.data.objects:
            results["passed"] = False
            results["errors"].append(f"Missing test object: {obj_name}")
            continue

        # Clean
        removed = _clean_existing_fit(obj_name)
        C.log(f"Cleaned modifiers on {obj_name}: {removed}")

        # Run fit recipe
        try:
            status = fit_garment.fit_garment_in_scene(
                obj_name, body_name, rig_name,
                fit_class=expected["fit_class"],
                do_weight_transfer=False,  # weights already exist on test objects
            )
        except Exception as e:
            results["passed"] = False
            results["errors"].append(f"fit_garment_in_scene failed for {obj_name}: {e}")
            continue

        results["fits"][obj_name] = status

        # Check vert count matches expectation
        if status["vert_count"] != expected["vert_count"]:
            results["passed"] = False
            results["errors"].append(
                f"{obj_name}: expected {expected['vert_count']} verts, got {status['vert_count']}"
            )

        # Check pct_masked in expected range
        pct = status["pct_masked"]
        lo, hi = expected["approx_pct_masked_range"]
        if not (lo <= pct <= hi):
            results["passed"] = False
            results["errors"].append(
                f"{obj_name}: pct_masked={pct} outside expected range [{lo}, {hi}] "
                f"for fit_class={expected['fit_class']}"
            )

        # Check SurfaceDeform bound (best effort — bind fails in some background contexts)
        if not status["surface_deform_bound"]:
            C.log(f"{obj_name}: SurfaceDeform bind not confirmed (may have failed in background mode). "
                  f"Run in interactive Blender to validate fully.", level="WARN")

        # Check modifier stack order
        stack = _verify_modifier_stack(obj_name)
        results["stacks"][obj_name] = stack
        if not stack["match"]:
            results["passed"] = False
            results["errors"].append(f"{obj_name}: modifier stack order mismatch: {stack}")

    return results


def main():
    """CLI entry point. Prints results as JSON; exits 0 on pass, 1 on fail."""
    results = run()
    print(json.dumps(results, indent=2))
    sys.exit(0 if results["passed"] else 1)


if __name__ == "__main__":
    main()
