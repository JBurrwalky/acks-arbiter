"""
decimate_clean.py — quad-preserving mesh decimation to a target polycount.

Implements §9.3 of gdd-character-creation-pipeline.md:
  1. Tris-to-Quads if mesh is triangulated (angle limit 40°)
  2. Planar Decimate (collapses coplanar faces)
  3. If still over target, Collapse Decimate with computed ratio
  4. Remove doubles, recompute normals

Two invocation modes:

  1. As a CLI (rare; usually called as a function):
       blender <file>.blend --background --python decimate_clean.py -- --object <name> --target 7000

  2. As importable function:
       import decimate_clean
       decimate_clean.decimate_to_target(armor_obj, target_polycount=7000)
"""

import bpy
import os
import sys

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)
import _common as C


def decimate_to_target(obj, target_polycount, *, tris_to_quads=True,
                        planar_angle_deg=5.0, post_cleanup=True):
    """Decimate `obj` (a Mesh object) toward `target_polycount` triangles.

    Strategy:
      1. (Optional) Tris-to-Quads on triangulated input
      2. Planar Decimate at small angle (cleans up coplanar quads cheaply)
      3. Collapse Decimate with computed ratio to hit target
      4. Cleanup: remove doubles, recompute normals

    Returns a status dict with before/after polycounts.
    """
    if obj.type != 'MESH':
        raise ValueError(f"decimate_to_target requires MESH; got {obj.type}")

    initial_polycount = len(obj.data.polygons)
    initial_verts = len(obj.data.vertices)

    if initial_polycount <= target_polycount:
        C.log(f"{obj.name}: already at {initial_polycount} polys (target {target_polycount}), no decimation")
        return {
            "obj": obj.name,
            "initial_polycount": initial_polycount,
            "final_polycount": initial_polycount,
            "actions": [],
        }

    C.set_active(obj)
    C.ensure_object_mode()

    actions = []

    # Step 1: Tris-to-Quads if input is triangulated
    if tris_to_quads:
        tri_ratio = _count_tris(obj.data) / max(1, initial_polycount)
        if tri_ratio > 0.5:
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            try:
                bpy.ops.mesh.tris_convert_to_quads(face_threshold=0.6981, shape_threshold=0.6981)  # ~40°
                actions.append("tris_to_quads")
            except RuntimeError as e:
                C.log(f"  tris_to_quads failed: {e}", level="WARN")
            bpy.ops.object.mode_set(mode='OBJECT')

    # Step 2: Planar Decimate (cheap, removes coplanar redundant geometry)
    planar = obj.modifiers.new(name="DecimatePlanar", type='DECIMATE')
    planar.decimate_type = 'DISSOLVE'
    planar.angle_limit = planar_angle_deg * 3.14159265 / 180.0
    planar.use_dissolve_boundaries = False
    bpy.ops.object.modifier_apply(modifier="DecimatePlanar")
    actions.append(f"planar_decimate@{planar_angle_deg}deg")

    after_planar = len(obj.data.polygons)

    # Step 3: Collapse Decimate to hit target if still over
    if after_planar > target_polycount:
        ratio = target_polycount / after_planar
        collapse = obj.modifiers.new(name="DecimateCollapse", type='DECIMATE')
        collapse.decimate_type = 'COLLAPSE'
        collapse.ratio = ratio
        collapse.use_collapse_triangulate = False  # keep quads where possible
        bpy.ops.object.modifier_apply(modifier="DecimateCollapse")
        actions.append(f"collapse_decimate@{ratio:.3f}")

    # Step 4: Cleanup
    if post_cleanup:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=0.0001)
        try:
            bpy.ops.mesh.normals_make_consistent(inside=False)
        except RuntimeError:
            pass
        bpy.ops.object.mode_set(mode='OBJECT')
        actions.append("cleanup_doubles_and_normals")

    final_polycount = len(obj.data.polygons)
    final_verts = len(obj.data.vertices)

    C.log(f"{obj.name}: {initial_polycount} → {final_polycount} polys "
          f"({100 * final_polycount / max(1, initial_polycount):.1f}% kept), "
          f"actions: {', '.join(actions)}")

    return {
        "obj": obj.name,
        "initial_polycount": initial_polycount,
        "initial_verts": initial_verts,
        "final_polycount": final_polycount,
        "final_verts": final_verts,
        "target_polycount": target_polycount,
        "actions": actions,
    }


def _count_tris(mesh):
    """Count triangles in a mesh (a triangle = polygon with exactly 3 verts)."""
    return sum(1 for p in mesh.polygons if len(p.vertices) == 3)


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
    p = argparse.ArgumentParser(description="Decimate a mesh to a target polycount.")
    p.add_argument("--object", required=True, help="Name of the mesh object to decimate")
    p.add_argument("--target", type=int, required=True, help="Target polycount")
    p.add_argument("--no-tris-to-quads", action="store_true", help="Skip the tris-to-quads pre-step")
    p.add_argument("--planar-angle", type=float, default=5.0, help="Planar decimate angle limit (deg)")
    return p.parse_args(argv)


def main_cli():
    args = _parse_argv()
    obj = C.get_object(args.object)
    decimate_to_target(
        obj, args.target,
        tris_to_quads=not args.no_tris_to_quads,
        planar_angle_deg=args.planar_angle,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main_cli())
