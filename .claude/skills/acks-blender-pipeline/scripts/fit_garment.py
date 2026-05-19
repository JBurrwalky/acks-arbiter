"""
fit_garment.py — soft-fit a garment FBX/OBJ/GLB to a target body, bind SurfaceDeform,
bake the modifier stack, and export glTF.

Implements §7 (soft-fit recipe) of generation/gdd-character-creation-pipeline.md.

Two invocation modes:

  1. As a CLI from blender --background:
       blender scratch.blend --background --python fit_garment.py -- \\
           --garment <path> --body <path.glb> --metadata <path.json> --output <out.glb>

  2. As importable functions from the Blender MCP:
       import sys
       sys.path.insert(0, r"<...>/.claude/skills/acks-blender-pipeline/scripts")
       import fit_garment
       fit_garment.fit_garment_in_scene(garment_obj_name="ARMOR2", body_obj_name="MESH - Female Basemesh",
                                        fit_class="plate", fit_mode="preserve")
"""

import bpy
import bmesh
import os
import sys
import json

# Make _common importable whether we're invoked via CLI or via MCP
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)
import _common as C


# ============================================================
# Core fit recipe — usable from MCP without file I/O
# ============================================================

def paint_fit_mask(garment_obj, body_obj, *, fit_mode="preserve", max_distance=0.010,
                   gamma=2.0, group_name="fit_mask"):
    """Paint the fit_mask vertex group on `garment_obj` based on signed distance to `body_obj`.

    fit_mode:
      - "preserve" — verts inside body get weight 0 (their sculpted position is kept; outer shell hides them).
        Use for armor sculpted for a different body anatomy (e.g., male armor on female body).
      - "conform"  — verts inside body get weight 1.0 (force-pushed out by Shrinkwrap).
        Use for armor sculpted FOR this body, or for cloth-like garments.

    Returns: (vgroup, masked_vert_count, inside_body_vert_count).
    """
    arm_mw = garment_obj.matrix_world
    body_mw = body_obj.matrix_world
    body_mw_inv = body_mw.inverted()
    body_mw_3x3 = body_mw.to_3x3()

    # Remove old group if present
    if group_name in garment_obj.vertex_groups:
        garment_obj.vertex_groups.remove(garment_obj.vertex_groups[group_name])
    vg = garment_obj.vertex_groups.new(name=group_name)

    weights = {}
    inside_count = 0
    for i, v in enumerate(garment_obj.data.vertices):
        v_world = arm_mw @ v.co
        v_in_body_local = body_mw_inv @ v_world

        hit, pt_local, normal_local, _ = body_obj.closest_point_on_mesh(v_in_body_local)
        if not hit:
            continue

        pt_world = body_mw @ pt_local
        body_normal_world = (body_mw_3x3 @ normal_local).normalized()
        from_body = v_world - pt_world
        dist = from_body.length
        signed = from_body.dot(body_normal_world)

        is_inside = signed < 0

        if fit_mode == "conform":
            if is_inside or dist < 0.0001:
                weights[i] = 1.0
            elif dist <= max_distance:
                w = (1.0 - dist / max_distance) ** gamma
                if w > 0.01:
                    weights[i] = min(1.0, w)
        elif fit_mode == "preserve":
            if is_inside:
                pass  # skip inside-body verts — preserve mode keeps them at sculpted position
            elif dist <= max_distance:
                w = (1.0 - dist / max_distance) ** gamma
                if w > 0.01:
                    weights[i] = min(1.0, w)
        else:
            raise ValueError(f"Unknown fit_mode: {fit_mode!r}; expected 'preserve' or 'conform'")

        if is_inside:
            inside_count += 1

    for v_idx, w in weights.items():
        vg.add([v_idx], w, 'REPLACE')

    return vg, len(weights), inside_count


def configure_shrinkwrap(garment_obj, body_obj, *, mask_name="fit_mask", offset=0.012,
                          mod_name="Shrinkwrap_SoftFit"):
    """Add (or replace) the Shrinkwrap_SoftFit modifier on garment_obj.

    Returns the modifier.
    """
    # Remove existing Shrinkwrap modifiers
    C.remove_modifier(garment_obj, mod_type='SHRINKWRAP')

    sw = garment_obj.modifiers.new(name=mod_name, type='SHRINKWRAP')
    sw.target = body_obj
    sw.wrap_method = 'NEAREST_SURFACEPOINT'
    sw.wrap_mode = 'OUTSIDE_SURFACE'
    sw.offset = offset
    sw.vertex_group = mask_name
    return sw


def configure_surface_deform(garment_obj, body_obj, *, mod_name="SurfaceDeform"):
    """Add (or replace) the SurfaceDeform modifier on garment_obj and bind it.

    Bind must happen with body in rest pose (shape keys at default values, no animation).
    Caller is responsible for ensuring rest-pose body state.

    Returns (modifier, was_bound_bool).
    """
    C.remove_modifier(garment_obj, mod_type='SURFACE_DEFORM')

    sd = garment_obj.modifiers.new(name=mod_name, type='SURFACE_DEFORM')
    sd.target = body_obj

    # Bind via operator; requires garment to be active
    C.set_active(garment_obj)
    try:
        bpy.ops.object.surfacedeform_bind(modifier=mod_name)
        bound = True
    except RuntimeError as e:
        C.log(f"SurfaceDeform bind failed for {garment_obj.name}: {e}", level="WARN")
        bound = False

    return sd, bound


def transfer_weights_from_body(garment_obj, body_obj):
    """Transfer vertex group weights from body to garment via Mesh Data Transfer.

    After this, garment has the same DEF-* vertex groups as body and can be skinned to the same rig.
    """
    C.set_active(garment_obj)
    # Add a Data Transfer modifier configured for vertex groups
    dt = garment_obj.modifiers.new(name="WeightTransfer", type='DATA_TRANSFER')
    dt.object = body_obj
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src = 'ALL'
    dt.layers_vgroup_select_dst = 'NAME'

    # The Data Transfer modifier needs vertex groups to copy weights INTO; create them first
    # by copying the body's vertex group names
    for vg in body_obj.vertex_groups:
        if vg.name not in garment_obj.vertex_groups:
            garment_obj.vertex_groups.new(name=vg.name)

    # Generate the data and apply
    try:
        bpy.ops.object.datalayout_transfer(modifier="WeightTransfer")
    except RuntimeError:
        pass  # Some Blender versions don't need or don't expose this
    bpy.ops.object.modifier_apply(modifier="WeightTransfer")


def configure_armature(garment_obj, rig_obj, *, mod_name="Armature"):
    """Add (or replace) the Armature modifier on garment_obj."""
    C.remove_modifier(garment_obj, mod_type='ARMATURE')
    arm = garment_obj.modifiers.new(name=mod_name, type='ARMATURE')
    arm.object = rig_obj
    arm.use_vertex_groups = True
    return arm


def auto_fit_scale_to_body(garment_obj, body_obj, rig_obj, target_bone_name,
                            clearance=1.10, z_band=0.15, body_bone_filter=None):
    """Scale `garment_obj` uniformly so its X-width matches the body's width at the target bone.

    Source armor packs are typically authored at heroic-male proportions; our 4 body types span a
    range. Without auto-scaling, the same armor mesh ends up oversized on slim/female bodies and
    tight on broad/dwarf bodies. This step makes one source mesh fit any body type — width-based
    so the armor's natural proportions are preserved.

    Critical detail: when measuring body width at chest level in T-pose, the arms extend out at
    chest height and would inflate the measurement. We filter to verts whose dominant bone weight
    is one of `body_bone_filter` (defaulting to spine bones for chest-level fitting). This isolates
    the torso width from the arm span.

    Operates on world-space vertex positions. Should run AFTER position_garment_at_bone() so the
    armor is already positioned around the target bone.

    Returns the applied scale_ratio, or None on failure.
    """
    from mathutils import Vector

    if rig_obj is None or target_bone_name not in rig_obj.data.bones:
        C.log(f"  auto_fit_scale: target_bone '{target_bone_name}' not found, skipping")
        return None

    # Default bone filter: chest fitting uses spine bones (excludes arms).
    # For other body regions: thigh fitting → thigh bones, etc. Auto-pick a sensible default
    # by target_bone family if caller didn't provide.
    if body_bone_filter is None:
        if target_bone_name.startswith("DEF-spine") or target_bone_name.startswith("DEF-breast"):
            body_bone_filter = {"DEF-spine", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003",
                                "DEF-spine.004", "DEF-spine.005", "DEF-spine.006",
                                "DEF-breast.L", "DEF-breast.R"}
        elif target_bone_name.startswith("DEF-pelvis") or target_bone_name == "DEF-spine":
            body_bone_filter = {"DEF-spine", "DEF-pelvis.L", "DEF-pelvis.R"}
        elif target_bone_name.startswith("DEF-thigh"):
            side = target_bone_name.split(".")[-1]  # "L" or "R"
            body_bone_filter = {f"DEF-thigh.{side}", f"DEF-thigh.{side}.001"}
        elif target_bone_name.startswith("DEF-shin"):
            side = target_bone_name.split(".")[-1]
            body_bone_filter = {f"DEF-shin.{side}", f"DEF-shin.{side}.001"}
        elif target_bone_name.startswith(("DEF-upper_arm", "DEF-shoulder")):
            side = target_bone_name.split(".")[-1]
            body_bone_filter = {f"DEF-upper_arm.{side}", f"DEF-upper_arm.{side}.001",
                                f"DEF-shoulder.{side}"}
        elif target_bone_name.startswith("DEF-forearm"):
            side = target_bone_name.split(".")[-1]
            body_bone_filter = {f"DEF-forearm.{side}", f"DEF-forearm.{side}.001"}
        elif target_bone_name == "DEF-head":
            body_bone_filter = {"DEF-head"}
        else:
            # Unknown bone — use everything; user can override via body_bone_filter
            body_bone_filter = None

    # Ensure garment transforms are baked so v.co is world space
    C.set_active(garment_obj)
    C.ensure_object_mode()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bone = rig_obj.data.bones[target_bone_name]
    bone_world_pos = rig_obj.matrix_world @ bone.head_local
    bone_z = bone_world_pos.z

    # Build body vertex group name lookup
    body_vg_name = {vg.index: vg.name for vg in body_obj.vertex_groups}

    def vert_dominant_bone(vert):
        best_bone = None
        best_weight = 0.0
        for g in vert.groups:
            name = body_vg_name.get(g.group, "")
            if g.weight > best_weight:
                best_weight = g.weight
                best_bone = name
        return best_bone

    body_mw = body_obj.matrix_world
    body_in_band = []
    for v in body_obj.data.vertices:
        v_world = body_mw @ v.co
        if abs(v_world.z - bone_z) >= z_band:
            continue
        if body_bone_filter is not None:
            if vert_dominant_bone(v) not in body_bone_filter:
                continue
        body_in_band.append(v_world)

    if not body_in_band:
        C.log(f"  auto_fit_scale: no body verts pass filter at z={bone_z}±{z_band}, skipping")
        return None
    body_w = max(c.x for c in body_in_band) - min(c.x for c in body_in_band)

    armor_in_band = [v.co for v in garment_obj.data.vertices if abs(v.co.z - bone_z) < z_band]
    if not armor_in_band:
        C.log(f"  auto_fit_scale: no armor verts within band — using full armor bbox width")
        coords = [v.co for v in garment_obj.data.vertices]
        armor_w = max(c.x for c in coords) - min(c.x for c in coords)
    else:
        armor_w = max(c.x for c in armor_in_band) - min(c.x for c in armor_in_band)

    if armor_w <= 0.001:
        C.log(f"  auto_fit_scale: armor width near zero, skipping")
        return None

    target_w = body_w * clearance
    scale_ratio = target_w / armor_w

    pivot = bone_world_pos
    for v in garment_obj.data.vertices:
        v.co = pivot + (v.co - pivot) * scale_ratio
    garment_obj.data.update()

    C.log(f"  auto_fit_scale: armor {armor_w:.3f}m → target {target_w:.3f}m "
          f"(body torso {body_w:.3f}m × {clearance} clearance from {len(body_in_band)} verts), "
          f"uniform scale {scale_ratio:.3f}")
    return scale_ratio


def position_garment_at_bone(garment_obj, rig_obj, target_bone_name):
    """Translate `garment_obj` so its world-space bbox center sits at `target_bone_name`'s
    rest-pose world position. Garment FBX files from external packs are typically authored at
    world origin (0,0,0); without this step the breastplate ends up at the feet instead of
    the chest. Bone names use the slim rig's `DEF-*` convention.

    Returns the applied delta vector for logging, or None if the bone is not found.
    """
    from mathutils import Vector
    if rig_obj is None or rig_obj.type != 'ARMATURE':
        C.log(f"  cannot position garment: rig is None or not an armature", level="WARN")
        return None
    if target_bone_name not in rig_obj.data.bones:
        available = [b.name for b in rig_obj.data.bones if b.name.startswith("DEF-spine")][:5]
        C.log(f"  target_bone '{target_bone_name}' not found in rig {rig_obj.name}; "
              f"available spine bones (first 5): {available}", level="WARN")
        return None

    bone = rig_obj.data.bones[target_bone_name]
    bone_world_pos = rig_obj.matrix_world @ bone.head_local

    # Compute armor's current world-space bbox center
    coords_world = [garment_obj.matrix_world @ v.co for v in garment_obj.data.vertices]
    bbox_min = Vector((
        min(c.x for c in coords_world),
        min(c.y for c in coords_world),
        min(c.z for c in coords_world),
    ))
    bbox_max = Vector((
        max(c.x for c in coords_world),
        max(c.y for c in coords_world),
        max(c.z for c in coords_world),
    ))
    bbox_center = (bbox_min + bbox_max) / 2.0

    delta = bone_world_pos - bbox_center
    garment_obj.location = garment_obj.location + delta
    C.set_active(garment_obj)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

    C.log(f"  positioned {garment_obj.name} at bone {target_bone_name} "
          f"(delta {tuple(round(c,3) for c in delta)})")
    return delta


def fit_garment_in_scene(garment_obj_name, body_obj_name, rig_obj_name=None, *,
                          fit_class=None, fit_mode=None, max_distance=None,
                          gamma=None, offset=None, target_bone=None,
                          auto_fit_scale=False, auto_fit_clearance=1.10,
                          do_surface_deform=True, do_weight_transfer=True):
    """Apply the full soft-fit recipe to a garment that's already loaded in the scene.

    Parameters can be supplied directly or fit_class can be used to look up defaults from
    references/fit_class_defaults.json. Direct params override class defaults.

    Modifier order after this function: [SurfaceDeform, Shrinkwrap_SoftFit, Armature].

    Returns a status dict with diagnostics.
    """
    garment = C.get_object(garment_obj_name)
    body = C.get_object(body_obj_name)
    rig = C.get_object(rig_obj_name) if rig_obj_name else None

    # Resolve parameters from fit_class defaults
    if fit_class is not None:
        defaults = C.load_fit_class_defaults()["fit_classes"]
        if fit_class not in defaults:
            raise ValueError(f"Unknown fit_class: {fit_class!r}; valid: {list(defaults.keys())}")
        cls = defaults[fit_class]
        fit_mode = fit_mode or cls["fit_mode"]
        max_distance = max_distance if max_distance is not None else cls["max_distance"]
        gamma = gamma if gamma is not None else cls["gamma"]
        offset = offset if offset is not None else cls["offset"]
    else:
        if any(p is None for p in (fit_mode, max_distance, gamma, offset)):
            raise ValueError("Must supply either fit_class or all of (fit_mode, max_distance, gamma, offset)")

    C.log(f"Fitting {garment.name} → {body.name}: mode={fit_mode}, "
          f"max_distance={max_distance}, gamma={gamma}, offset={offset}")

    # Step 0a: position the garment at its target bone before fitting. Garment FBX files are
    # typically authored at world origin; the target_bone (e.g., "DEF-spine.003" for a chest
    # piece) tells the script where on the body the garment's center should sit.
    if target_bone and rig is not None:
        position_garment_at_bone(garment, rig, target_bone)

    # Step 0b: auto-scale to body proportions. Source armor packs are authored at one canonical
    # body size (often heroic-male) but our 4 body types span female/dwarf/small-male/large-male.
    # Width-based uniform scaling makes one source mesh fit any body type.
    if auto_fit_scale and target_bone and rig is not None:
        auto_fit_scale_to_body(garment, body, rig, target_bone, clearance=auto_fit_clearance)

    # Step 1: transfer weights (only if requested AND garment doesn't already have body's groups)
    if do_weight_transfer:
        body_vg_names = {vg.name for vg in body.vertex_groups}
        garment_vg_names = {vg.name for vg in garment.vertex_groups}
        if not body_vg_names.issubset(garment_vg_names):
            C.log("Transferring vertex weights from body to garment")
            transfer_weights_from_body(garment, body)

    # Step 2: paint fit mask
    _, masked, inside = paint_fit_mask(
        garment, body, fit_mode=fit_mode, max_distance=max_distance, gamma=gamma
    )

    # Step 3: configure Shrinkwrap (before Armature in stack)
    sw = configure_shrinkwrap(garment, body, offset=offset)

    # Step 4: configure SurfaceDeform (before Shrinkwrap in stack) and bind
    sd_bound = False
    if do_surface_deform:
        sd, sd_bound = configure_surface_deform(garment, body)

    # Step 5: configure Armature (if rig supplied)
    if rig is not None:
        configure_armature(garment, rig)

    # Reorder modifier stack: SurfaceDeform → Shrinkwrap_SoftFit → Armature
    if do_surface_deform:
        C.move_modifier_before(garment, sd, 'SHRINKWRAP')
    C.move_modifier_before(garment, sw, 'ARMATURE')

    return {
        "garment": garment.name,
        "body": body.name,
        "rig": rig.name if rig else None,
        "fit_class": fit_class,
        "fit_mode": fit_mode,
        "params": {"max_distance": max_distance, "gamma": gamma, "offset": offset},
        "vert_count": len(garment.data.vertices),
        "masked_verts": masked,
        "inside_body_verts": inside,
        "pct_masked": round(100 * masked / max(1, len(garment.data.vertices)), 1),
        "pct_inside": round(100 * inside / max(1, len(garment.data.vertices)), 1),
        "surface_deform_bound": sd_bound,
        "modifier_stack": [(m.name, m.type) for m in garment.modifiers],
    }


def bake_modifier_stack(garment_obj_name):
    """Apply SurfaceDeform and Shrinkwrap_SoftFit (in that order) to bake the fit into the rest mesh.

    Leaves Armature in place (runtime-dynamic).

    Returns a status dict.
    """
    garment = C.get_object(garment_obj_name)
    C.set_active(garment)
    C.ensure_object_mode()

    applied = []
    # Apply SurfaceDeform first (it's the topmost in the stack)
    if C.find_modifier(garment, mod_type='SURFACE_DEFORM'):
        C.apply_modifier(garment, "SurfaceDeform")
        applied.append("SurfaceDeform")
    # Then Shrinkwrap
    if C.find_modifier(garment, mod_type='SHRINKWRAP'):
        sw_name = C.find_modifier(garment, mod_type='SHRINKWRAP').name
        C.apply_modifier(garment, sw_name)
        applied.append(sw_name)

    return {
        "garment": garment.name,
        "applied": applied,
        "remaining_modifiers": [(m.name, m.type) for m in garment.modifiers],
    }


# ============================================================
# CLI mode — import → fit → bake → export pipeline
# ============================================================

def _parse_argv():
    """Parse CLI arguments passed after `--` to a blender --background invocation."""
    import argparse
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser(description="Soft-fit a garment to a body and export glTF.")
    p.add_argument("--garment", required=True, help="Path to source garment FBX/OBJ/GLB")
    p.add_argument("--body", required=True, help="Path to baked body glTF")
    p.add_argument("--metadata", required=True, help="Path to per-asset metadata JSON")
    p.add_argument("--output", required=True, help="Path to output fitted glTF")
    p.add_argument("--no-export", action="store_true", help="Skip the final glTF export (for debugging)")
    return p.parse_args(argv)


def _import_garment(path):
    """Dispatch import based on file extension. Returns the imported mesh object."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        new_names = C.import_fbx(path)
    elif ext == ".obj":
        new_names = C.import_obj(path)
    elif ext in (".glb", ".gltf"):
        new_names = C.import_glb(path)
    else:
        raise ValueError(f"Unsupported garment file extension: {ext}")

    mesh_objects = [bpy.data.objects[n] for n in new_names if bpy.data.objects[n].type == 'MESH']
    if not mesh_objects:
        raise RuntimeError(f"No mesh objects imported from {path}")
    if len(mesh_objects) > 1:
        C.log(f"Multiple mesh objects imported ({len(mesh_objects)}); using first: {mesh_objects[0].name}",
              level="WARN")
    return mesh_objects[0]


def _import_body(path):
    """Import body glTF; returns (body_mesh, rig_armature).

    The body mesh is identified as the LARGEST mesh (most vertices) — robust against extra
    meshes that may slip into the glb (addon widgets, evaluation artifacts). The rig is the
    first armature found.
    """
    new_names = C.import_glb(path)
    body_mesh = None
    rig = None
    for name in new_names:
        obj = bpy.data.objects[name]
        if obj.type == 'MESH':
            if body_mesh is None or len(obj.data.vertices) > len(body_mesh.data.vertices):
                body_mesh = obj
        elif obj.type == 'ARMATURE' and rig is None:
            rig = obj
    if body_mesh is None:
        raise RuntimeError(f"No body mesh found in {path}")
    C.log(f"Body mesh selected: {body_mesh.name} ({len(body_mesh.data.vertices)} verts)")
    return body_mesh, rig


def main_cli():
    """CLI entry point."""
    args = _parse_argv()

    if not os.path.exists(args.garment):
        C.die(f"Garment file not found: {args.garment}")
    if not os.path.exists(args.body):
        C.die(f"Body file not found: {args.body}")
    if not os.path.exists(args.metadata):
        C.die(f"Metadata file not found: {args.metadata}")

    metadata = C.load_json(args.metadata)
    C.log(f"Processing {metadata.get('id', 'unknown')} → {args.output}")

    # Start from empty scene
    C.reset_to_empty_scene()

    # Import garment
    garment = _import_garment(args.garment)
    # scale_factor is a MULTIPLIER on the imported scale (per gdd-character-creation-pipeline.md §10.1).
    # FBX importers set object scale to 0.01 when the file's unit is cm (typical for armor packs);
    # the metadata's scale_factor=100 brings it back to 1.0. scale_factor=1.0 = no change.
    scale_mult = metadata["source"].get("scale_factor", 1.0)
    if scale_mult != 1.0:
        s = garment.scale[0] * scale_mult
        garment.scale = (s, s, s)
        C.set_active(garment)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        C.log(f"Scaled garment by {scale_mult}× → effective scale {s}, dims {tuple(round(d,3) for d in garment.dimensions)}")

    # Auto UV if needed
    if metadata["source"].get("needs_uv_unwrap", False):
        try:
            import auto_uv
            auto_uv.smart_uv_project(garment)
        except ImportError:
            C.log("auto_uv module not yet implemented; skipping UV unwrap", level="WARN")

    # Decimate if over target
    target_polycount = metadata.get("polycount_target")
    if target_polycount and len(garment.data.polygons) > target_polycount:
        try:
            import decimate_clean
            decimate_clean.decimate_to_target(garment, target_polycount)
        except ImportError:
            C.log("decimate_clean module not yet implemented; skipping decimation", level="WARN")

    # Import body + rig
    body, rig = _import_body(args.body)

    # Fit
    status = fit_garment_in_scene(
        garment.name, body.name, rig.name if rig else None,
        fit_class=metadata.get("fit_class"),
        fit_mode=metadata.get("fit_mode"),
        **{k: v for k, v in metadata.get("fit_params", {}).items()
           if k in ("max_distance", "gamma", "offset", "target_bone",
                    "auto_fit_scale", "auto_fit_clearance")}
    )
    C.log(f"Fit status: {json.dumps(status, indent=2)}")

    # Bake modifier stack (SurfaceDeform + Shrinkwrap)
    bake_status = bake_modifier_stack(garment.name)
    C.log(f"Bake status: {json.dumps(bake_status, indent=2)}")

    # Export
    if not args.no_export:
        out_dir = os.path.dirname(args.output)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        C.set_active(garment)
        # Select garment + rig for export so the rig is included
        if rig is not None:
            rig.select_set(True)
        gltf_kwargs = dict(
            filepath=args.output,
            export_format='GLB',
            use_selection=True,
            export_apply=False,  # Armature must NOT be applied
            export_yup=True,
            export_skins=True,
            export_morph=False,
            export_animations=False,
        )
        # Blender 5.1 renamed export_colors → export_attributes; try modern first.
        try:
            bpy.ops.export_scene.gltf(**gltf_kwargs, export_attributes=True)
        except TypeError:
            bpy.ops.export_scene.gltf(**gltf_kwargs)
        C.log(f"Exported {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main_cli())
