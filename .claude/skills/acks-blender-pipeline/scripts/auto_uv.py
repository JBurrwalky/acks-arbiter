"""
auto_uv.py — Smart UV Project for meshes without UV layers.

Implements §9.4 of gdd-character-creation-pipeline.md. Used by fit_garment.py and
bake_body_type.py for assets imported without UVs (most of the low-poly armor packs).

Settings tuned for hard-surface low-poly armor: angle_limit=66°, island_margin=0.02.
For organic / curved surfaces, callers can override.
"""

import bpy
import os
import sys

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)
import _common as C


def smart_uv_project(obj, *, angle_limit_deg=66.0, island_margin=0.02,
                      area_weight=0.0, correct_aspect=True, force=False,
                      layer_name="UVMap"):
    """Run Smart UV Project on `obj`. If obj already has UVs and force=False, no-op.

    Returns (created_new_layer, applied).
    """
    if obj.type != 'MESH':
        raise ValueError(f"smart_uv_project requires MESH; got {obj.type}")

    me = obj.data
    has_uvs = len(me.uv_layers) > 0

    if has_uvs and not force:
        C.log(f"{obj.name}: already has UVs ({me.uv_layers[0].name}), skipping unwrap")
        return False, False

    # Add a UV layer if none exists
    if not has_uvs:
        me.uv_layers.new(name=layer_name)

    C.set_active(obj)
    C.ensure_object_mode()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')

    angle_rad = angle_limit_deg * 3.14159265 / 180.0
    try:
        bpy.ops.uv.smart_project(
            angle_limit=angle_rad,
            island_margin=island_margin,
            area_weight=area_weight,
            correct_aspect=correct_aspect,
            scale_to_bounds=False,
        )
        applied = True
    except RuntimeError as e:
        C.log(f"  smart_uv_project failed for {obj.name}: {e}", level="WARN")
        applied = False

    bpy.ops.object.mode_set(mode='OBJECT')
    C.log(f"{obj.name}: smart UV project applied={applied} "
          f"(angle={angle_limit_deg}°, margin={island_margin})")

    return (not has_uvs), applied


# ============================================================
# CLI
# ============================================================

def _parse_argv():
    import argparse
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser(description="Smart UV Project on a mesh.")
    p.add_argument("--object", required=True, help="Name of the mesh object")
    p.add_argument("--angle", type=float, default=66.0, help="Angle limit (deg)")
    p.add_argument("--margin", type=float, default=0.02, help="Island margin")
    p.add_argument("--force", action="store_true", help="Re-unwrap even if UVs exist")
    return p.parse_args(argv)


def main_cli():
    args = _parse_argv()
    obj = C.get_object(args.object)
    smart_uv_project(obj, angle_limit_deg=args.angle, island_margin=args.margin, force=args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main_cli())
