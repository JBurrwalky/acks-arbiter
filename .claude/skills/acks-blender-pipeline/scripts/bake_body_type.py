"""
bake_body_type.py — bake one body type from a Customisable Basemesh source.

Implements §5.4 of gdd-character-creation-pipeline.md (the 12-step procedure):
  1. Open <basemesh>.blend (with Customisable Basemesh addon enabled)
  2. Apply slider preset (set shape key values from the body type's preset spec)
  3. Apply all shape keys to flatten (destroys the slider system on the bake copy)
  4. Duplicate the rig, name it <body_id>_rig
  5. On duplicate rig: mark bones for deletion per §5.2 drop list
  6. Switch to Edit Mode, delete marked bones
  7. Re-parent body mesh to slim rig (Armature modifier; vg names match DEF-* so weights preserved)
  8. Delete unused vertex groups (those whose bones were dropped)
  9. Decimate body mesh to target polycount via decimate_clean.py
 10. Paint or import hide-region vertex groups (interactive — deferred to paint_hide_regions.py)
 11. Set up vertex color channels per §3.4
 12. Export glTF to assets/characters/bodies/<body_id>.glb

CLI:
    blender <basemesh.blend> --background --python bake_body_type.py -- \\
        --body-id large_human_male \\
        --preset references/body_type_presets/large_human_male.json \\
        --output assets/characters/bodies/large_human_male.glb

Open question §15.1: this script implements the DIY rig-slimming path. If the project decides
to adopt Auto-Rig Pro, the slim_rig() function would be replaced by an Auto-Rig Pro export call;
the rest of the pipeline stays identical.
"""

import bpy
import os
import sys
import json

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)
import _common as C


# =============================================================================
# §5.1: Bones to KEEP (the slim rig — ~50 deform bones, under the 60-bone cap)
# =============================================================================
# Construction: a fixed list plus parametric expansion for L/R sides and numbered chain segments.

def build_keep_bone_set():
    """Return the set of bone names to retain in the slim rig.

    Based on gdd-character-creation-pipeline.md §5.1. Bone names use Rigify's DEF- prefix
    (e.g., 'DEF-spine.001', 'DEF-thigh.L'). Bones not in this set are dropped.
    """
    keep = set()

    # Spine: 7 bones (DEF-spine, DEF-spine.001..006). spine.005 = upper back for quiver attachment.
    keep.add("DEF-spine")
    for i in range(1, 7):
        keep.add(f"DEF-spine.00{i}")

    # Pelvis: 2 bones (L+R)
    for side in ("L", "R"):
        keep.add(f"DEF-pelvis.{side}")

    # Legs per side: thigh + thigh.001 (twist), shin + shin.001 (twist), foot, toe
    for side in ("L", "R"):
        keep.add(f"DEF-thigh.{side}")
        keep.add(f"DEF-thigh.{side}.001")
        keep.add(f"DEF-shin.{side}")
        keep.add(f"DEF-shin.{side}.001")
        keep.add(f"DEF-foot.{side}")
        keep.add(f"DEF-toe.{side}")

    # Arms per side: shoulder, upper_arm + upper_arm.001, forearm + forearm.001, hand
    for side in ("L", "R"):
        keep.add(f"DEF-shoulder.{side}")
        keep.add(f"DEF-upper_arm.{side}")
        keep.add(f"DEF-upper_arm.{side}.001")
        keep.add(f"DEF-forearm.{side}")
        keep.add(f"DEF-forearm.{side}.001")
        keep.add(f"DEF-hand.{side}")

    # Fingers per side: base joint of thumb, index, middle, ring, pinky
    for side in ("L", "R"):
        keep.add(f"DEF-thumb.01.{side}")
        keep.add(f"DEF-f_index.01.{side}")
        keep.add(f"DEF-f_middle.01.{side}")
        keep.add(f"DEF-f_ring.01.{side}")
        keep.add(f"DEF-f_pinky.01.{side}")

    # Neck + Head
    keep.add("DEF-neck")
    keep.add("DEF-head")

    # Face (minimal): jaw, eyes
    keep.add("DEF-jaw")
    keep.add("DEF-eye.L")
    keep.add("DEF-eye.R")

    # Breast (optional cloth-sim hooks — drop for dwarf male via preset override)
    keep.add("DEF-breast.L")
    keep.add("DEF-breast.R")

    return keep


# =============================================================================
# Slider preset application
# =============================================================================

def apply_shape_key_preset(body_obj, preset_dict):
    """Set body's shape keys to the values in preset_dict.

    preset_dict comes from the body type preset JSON (e.g., references/body_type_presets/large_human_male.json).
    Values not found in body's shape keys are logged and skipped.

    elf_variant_overrides (if present in preset_dict) are NOT applied here — caller decides.
    """
    if not body_obj.data.shape_keys:
        C.log(f"{body_obj.name}: no shape keys to apply", level="WARN")
        return {}

    applied = {}
    missing = []
    for key_name, value in preset_dict.get("shape_keys", {}).items():
        sk = body_obj.data.shape_keys.key_blocks.get(key_name)
        if sk is None:
            missing.append(key_name)
            continue
        sk.value = float(value)
        applied[key_name] = value

    if missing:
        C.log(f"  shape keys not found on {body_obj.name}: {missing}", level="WARN")

    C.log(f"{body_obj.name}: applied {len(applied)} shape key values")
    return applied


def flatten_shape_keys(obj):
    """Bake all current shape key values into the base mesh and remove the shape key data.

    After this, the slider system is gone; the mesh is frozen at whatever pose was set.
    """
    if not obj.data.shape_keys:
        return 0

    C.set_active(obj)
    C.ensure_object_mode()

    sk_count = len(obj.data.shape_keys.key_blocks)

    # Blender 4.0+ has shape_key_apply_all; falls back to manual approach otherwise.
    try:
        bpy.ops.object.shape_key_apply_all()
        C.log(f"{obj.name}: flattened {sk_count} shape keys via shape_key_apply_all()")
        return sk_count
    except (RuntimeError, AttributeError):
        pass

    # Manual fallback: evaluate the mesh with current shape key values, replace the mesh data,
    # then remove the shape key data block.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    obj_eval = obj.evaluated_get(depsgraph)
    new_mesh = bpy.data.meshes.new_from_object(obj_eval)
    new_mesh.name = obj.data.name + "_baked"

    # Preserve vertex groups (Mesh.new_from_object copies them) and materials
    old_mesh = obj.data
    obj.data = new_mesh
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
    C.log(f"{obj.name}: flattened {sk_count} shape keys via manual bake")
    return sk_count


# =============================================================================
# Rig slimming
# =============================================================================

def slim_rig(rig_obj, keep_bones, *, new_name=None):
    """Remove all bones from `rig_obj` whose names are not in `keep_bones`.

    Re-parents children of dropped bones to the nearest kept ancestor before deletion,
    so the slim hierarchy stays connected.

    Returns a status dict: {kept: int, dropped: int, dropped_names: list}.
    """
    if rig_obj.type != 'ARMATURE':
        raise ValueError(f"slim_rig requires ARMATURE; got {rig_obj.type}")

    if new_name:
        rig_obj.name = new_name
        rig_obj.data.name = new_name + "_data"

    C.set_active(rig_obj)
    C.ensure_object_mode()
    bpy.ops.object.mode_set(mode='EDIT')

    edit_bones = rig_obj.data.edit_bones
    all_names = [b.name for b in edit_bones]
    dropped_names = [n for n in all_names if n not in keep_bones]

    # Re-parent kept children of dropped bones to their nearest kept ancestor
    def nearest_kept_ancestor(bone):
        cur = bone.parent
        while cur is not None:
            if cur.name in keep_bones:
                return cur
            cur = cur.parent
        return None

    for name in dropped_names:
        bone = edit_bones.get(name)
        if bone is None:
            continue
        for child in list(bone.children):
            if child.name in keep_bones:
                new_parent = nearest_kept_ancestor(bone)
                child.parent = new_parent

    # Now safely remove the dropped bones
    for name in dropped_names:
        bone = edit_bones.get(name)
        if bone is not None:
            edit_bones.remove(bone)

    bpy.ops.object.mode_set(mode='OBJECT')

    kept = len([b for b in rig_obj.data.bones])
    C.log(f"{rig_obj.name}: slimmed rig {len(all_names)} → {kept} bones "
          f"({len(dropped_names)} dropped)")

    return {
        "rig": rig_obj.name,
        "initial_bone_count": len(all_names),
        "final_bone_count": kept,
        "dropped_count": len(dropped_names),
    }


def remove_unused_vertex_groups(mesh_obj, keep_bones, preserve_groups=None):
    """Remove vertex groups whose names don't match a kept bone or a preserve_groups entry.

    The Customisable Basemesh body mesh has 174 vertex groups, one per deform bone. After rig
    slimming, the groups for dropped bones are unreferenced and should be cleaned up.
    preserve_groups lets specific non-bone groups (e.g., 'Outline Thickness') survive the cull.
    """
    if mesh_obj.type != 'MESH':
        return 0
    preserve_groups = preserve_groups or set()
    to_remove = [vg for vg in mesh_obj.vertex_groups
                 if vg.name not in keep_bones and vg.name not in preserve_groups]
    for vg in to_remove:
        mesh_obj.vertex_groups.remove(vg)
    C.log(f"{mesh_obj.name}: removed {len(to_remove)} unused vertex groups, "
          f"{len(mesh_obj.vertex_groups)} remain")
    return len(to_remove)


# Bone → hide-region mapping per gdd-character-creation-pipeline.md §8.1.
# A vertex's hide region is determined by its DOMINANT bone weight (the bone it's most weighted to).
# Region IDs 0-9 match the §8.1 table; verts with no matching bone get 255 = "always visible".
_BONE_TO_REGION = {
    # 0 = head
    "DEF-head": 0, "DEF-jaw": 0, "DEF-eye.L": 0, "DEF-eye.R": 0,
    # 1 = neck
    "DEF-neck": 1,
    # 2 = chest (mid-back through upper chest + breast bones for cloth simulation rigging)
    "DEF-spine.002": 2, "DEF-spine.003": 2, "DEF-spine.004": 2,
    "DEF-spine.005": 2, "DEF-spine.006": 2,
    "DEF-breast.L": 2, "DEF-breast.R": 2,
    # 3 = waist
    "DEF-spine": 3, "DEF-spine.001": 3,
    "DEF-pelvis.L": 3, "DEF-pelvis.R": 3,
    # 4 = upper arms (shoulder + upper_arm)
    "DEF-shoulder.L": 4, "DEF-upper_arm.L": 4, "DEF-upper_arm.L.001": 4,
    "DEF-shoulder.R": 4, "DEF-upper_arm.R": 4, "DEF-upper_arm.R.001": 4,
    # 5 = forearms
    "DEF-forearm.L": 5, "DEF-forearm.L.001": 5,
    "DEF-forearm.R": 5, "DEF-forearm.R.001": 5,
    # 6 = hands (palm + fingers)
    "DEF-hand.L": 6, "DEF-hand.R": 6,
    "DEF-thumb.01.L": 6, "DEF-f_index.01.L": 6, "DEF-f_middle.01.L": 6,
    "DEF-f_ring.01.L": 6, "DEF-f_pinky.01.L": 6,
    "DEF-thumb.01.R": 6, "DEF-f_index.01.R": 6, "DEF-f_middle.01.R": 6,
    "DEF-f_ring.01.R": 6, "DEF-f_pinky.01.R": 6,
    # 7 = thighs
    "DEF-thigh.L": 7, "DEF-thigh.L.001": 7,
    "DEF-thigh.R": 7, "DEF-thigh.R.001": 7,
    # 8 = calves
    "DEF-shin.L": 8, "DEF-shin.L.001": 8,
    "DEF-shin.R": 8, "DEF-shin.R.001": 8,
    # 9 = feet
    "DEF-foot.L": 9, "DEF-toe.L": 9,
    "DEF-foot.R": 9, "DEF-toe.R": 9,
}


_HIDE_REGION_NAMES = [
    "hide_head", "hide_neck", "hide_chest", "hide_waist", "hide_upper_arms",
    "hide_forearms", "hide_hands", "hide_thighs", "hide_calves", "hide_feet",
]


def auto_classify_hide_regions(mesh_obj):
    """Assign each vertex to a hide region (0-9). Painted `hide_*` vertex groups win;
    otherwise fall back to dominant-bone-weight classification.

    Manual paint workflow:
      1. Open the source basemesh .blend
      2. Select the body mesh, switch to Weight Paint mode
      3. Create vertex groups named `hide_head`, `hide_neck`, `hide_chest`, `hide_waist`,
         `hide_upper_arms`, `hide_forearms`, `hide_hands`, `hide_thighs`, `hide_calves`,
         `hide_feet` (10 total)
      4. Paint each region — verts with weight ≥ 0.5 are considered "in that region"
      5. Save the .blend
      6. Re-run bake_body_type.py — painted groups override the heuristic, unpainted areas
         fall back to the bone-weight classification

    Painted overrides take precedence: if a vertex is in MULTIPLE hide_* groups (e.g., armpit
    painted in both hide_chest and hide_upper_arms), the one with the highest weight wins.

    Returns a dict {vertex_index: region_id}.
    """
    vg_name_by_index = {vg.index: vg.name for vg in mesh_obj.vertex_groups}
    name_to_region = {name: i for i, name in enumerate(_HIDE_REGION_NAMES)}

    region_by_vert = {}
    painted_count = 0
    for v_idx, vert in enumerate(mesh_obj.data.vertices):
        # First pass: check for painted hide_* groups
        best_painted_region = None
        best_painted_weight = 0.5  # threshold — below this, not considered "in region"
        for g in vert.groups:
            name = vg_name_by_index.get(g.group, "")
            if name in name_to_region and g.weight >= best_painted_weight:
                best_painted_weight = g.weight
                best_painted_region = name_to_region[name]
        if best_painted_region is not None:
            region_by_vert[v_idx] = best_painted_region
            painted_count += 1
            continue

        # Fall back to bone-weight heuristic
        best_bone = None
        best_weight = 0.0
        for g in vert.groups:
            bone_name = vg_name_by_index.get(g.group)
            if bone_name and bone_name.startswith("DEF-") and g.weight > best_weight:
                best_weight = g.weight
                best_bone = bone_name
        region_by_vert[v_idx] = _BONE_TO_REGION.get(best_bone, 255)

    # Histogram for logging
    from collections import Counter
    histogram = Counter(region_by_vert.values())
    region_names = ["head", "neck", "chest", "waist", "upper_arms", "forearms",
                    "hands", "thighs", "calves", "feet"]
    summary = ", ".join(
        f"{region_names[r]}={histogram.get(r, 0)}" for r in range(10)
    )
    if 255 in histogram:
        summary += f", always_visible={histogram[255]}"
    source_note = f"painted={painted_count}, auto={len(region_by_vert) - painted_count}"
    C.log(f"  hide-region classification ({source_note}): {summary}")

    return region_by_vert


def bake_vertex_color_attribute(mesh_obj, *, outline_vgroup="Outline Thickness"):
    """Consolidate the body's vertex-color attributes to ONE attribute named 'Color'
    that encodes our pipeline's region/outline semantics per gdd-character-creation-pipeline.md §3.4:

      - channel R: hide-region ID (0-9, 255 = always visible). Default 255 — populated by paint_hide_regions.py.
      - channel G: region semantic (0=skin, 0.25=hair, 0.5=eyes, 0.75=lips, 1.0=other). Default 0 (skin).
      - channel B: outline thickness multiplier (0.0 = no outline at this vertex, 1.0 = full thickness).
                   Sourced from the `Outline Thickness` vertex group if present, else 1.0 everywhere.
      - channel A: reserved (1.0).

    The basemesh ships up to 3 unrelated color attributes from Cycles material setups; we drop
    them in favor of this single canonical layer.

    Must run AFTER `flatten_shape_keys` (which replaces the mesh data and clears prior color
    attributes) but BEFORE `remove_unused_vertex_groups` (which would otherwise drop the
    `Outline Thickness` group). Operates on the slim rig's body mesh in object mode.
    """
    me = mesh_obj.data

    # Drop any existing color attributes — basemesh's Cycles attrs aren't useful for our shader.
    while len(me.color_attributes) > 0:
        me.color_attributes.remove(me.color_attributes[0])

    # Read the outline thickness weights, if the group exists.
    weights = {}
    if outline_vgroup in mesh_obj.vertex_groups:
        vg = mesh_obj.vertex_groups[outline_vgroup]
        vg_idx = vg.index
        for v_idx, vert in enumerate(me.vertices):
            for g in vert.groups:
                if g.group == vg_idx:
                    weights[v_idx] = g.weight
                    break
        C.log(f"  outline thickness weights captured from '{outline_vgroup}': {len(weights)} verts")
    else:
        C.log(f"  no '{outline_vgroup}' group found — defaulting outline weights to 1.0 everywhere")

    # Auto-classify hide regions from dominant bone weights.
    region_by_vert = auto_classify_hide_regions(mesh_obj)

    # Create the canonical color attribute. CORNER domain (per face-corner) is Blender's
    # convention for "primary vertex color" — the gltf exporter writes it as COLOR_0 which
    # Godot reads as the COLOR vertex shader varying. POINT-domain attributes get exported
    # as auxiliary "Color.001" attributes that Godot doesn't expose by default.
    col_attr = me.color_attributes.new(name="Color", type='BYTE_COLOR', domain='CORNER')

    # Each face corner gets the value of its underlying vertex. R encoding per-byte:
    #   R: hide-region ID (0-9, or 255 = always visible)
    #   G: 0 (skin semantic — paint_hide_regions.py will overwrite for hair/eye/lip)
    #   B: outline thickness weight (0 = no outline, 1.0 = full)
    #   A: 1.0 (reserved)
    for loop in me.loops:
        v_idx = loop.vertex_index
        outline_w = weights.get(v_idx, 1.0)
        region_id = region_by_vert.get(v_idx, 255)
        region_norm = region_id / 255.0
        col_attr.data[loop.index].color = (region_norm, 0.0, outline_w, 1.0)

    C.log(f"{mesh_obj.name}: baked canonical 'Color' attribute (CORNER domain, "
          f"R=hide_region, G=semantic, B=outline_thickness, {len(me.loops)} corners)")


# =============================================================================
# Main bake pipeline
# =============================================================================

def find_body_and_rig():
    """Heuristically find the body mesh and rig in the current scene.

    The Customisable Basemesh convention:
      - Body mesh name contains "Basemesh" and is type MESH
      - Rig is an ARMATURE not named "metarig"
    """
    body = None
    rig = None
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and "Basemesh" in obj.name and "WGT" not in obj.name:
            if body is None or len(obj.data.vertices) > len(body.data.vertices):
                body = obj
        elif obj.type == 'ARMATURE' and obj.name != "metarig":
            if rig is None or len(obj.data.bones) > len(rig.data.bones):
                rig = obj
    return body, rig


def bake_body_type(preset_path, output_path, *, decimate=True, body_obj_name=None,
                    rig_obj_name=None, drop_breast_bones=False):
    """Bake the current scene's basemesh into the body type specified by preset.

    Caller is responsible for having opened the source basemesh .blend file before calling this.
    """
    preset = C.load_json(preset_path)
    body_id = preset["body_id"]
    target_polycount = preset.get("polycount_target", 7000)

    # Locate body and rig
    if body_obj_name:
        body = C.get_object(body_obj_name)
    else:
        body, rig_auto = find_body_and_rig()
        if body is None:
            raise RuntimeError("Could not auto-locate body mesh; pass body_obj_name explicitly")

    if rig_obj_name:
        rig = C.get_object(rig_obj_name)
    else:
        _, rig = find_body_and_rig()
        if rig is None:
            raise RuntimeError("Could not auto-locate rig armature; pass rig_obj_name explicitly")

    C.log(f"Baking body_id={body_id}: body={body.name}, rig={rig.name}, target_polys={target_polycount}")

    # Step 2: apply slider preset
    apply_shape_key_preset(body, preset)

    # Step 3: flatten shape keys
    flatten_shape_keys(body)

    # Build keep set
    keep_bones = build_keep_bone_set()
    if drop_breast_bones:
        keep_bones.discard("DEF-breast.L")
        keep_bones.discard("DEF-breast.R")

    # Step 4-6: slim the rig
    slim_status = slim_rig(rig, keep_bones, new_name=f"{body_id}_rig")

    # Step 7: re-parent body to the slim rig is unnecessary because the body's Armature modifier
    # already targets `rig`; we slimmed `rig` in place, so the modifier is still valid.

    # Step 8: remove unused vertex groups. Preserve `Outline Thickness` so its per-vertex
    # weights can be baked into the canonical Color attribute AFTER decimation. Bone vertex
    # groups stay (decimate preserves them, glTF needs them for skinning).
    removed_vgs = remove_unused_vertex_groups(body, keep_bones,
                                               preserve_groups={"Outline Thickness"})

    # Step 9: decimate
    decimate_status = None
    if decimate and len(body.data.polygons) > target_polycount:
        try:
            import decimate_clean
            decimate_status = decimate_clean.decimate_to_target(body, target_polycount)
        except ImportError:
            C.log("decimate_clean module not available; skipping decimation", level="WARN")

    # Step 9.5: bake the canonical Color attribute AFTER decimation. Decimate-Collapse merges
    # vertices and averages their colors, so baking BEFORE decimate produces smudged region IDs
    # at boundaries (a chest vert at 0.00784 averaged with a waist vert at 0.01176 lands at
    # 0.0098, which int-rounds to region 3 — wrong region). Baking AFTER decimate guarantees
    # each surviving vertex gets a clean integer region ID. The hide-region auto-classification
    # uses the post-decimate dominant bone weights, which reflect actual final geometry.
    bake_vertex_color_attribute(body)

    # Step 10: hide region painting is interactive — deferred to paint_hide_regions.py
    # (We DO create the empty vertex groups so the artist has them to paint into.)
    hide_region_names = [
        "hide_head", "hide_neck", "hide_chest", "hide_waist",
        "hide_upper_arms", "hide_forearms", "hide_hands",
        "hide_thighs", "hide_calves", "hide_feet",
    ]
    for name in hide_region_names:
        if name not in body.vertex_groups:
            body.vertex_groups.new(name=name)
    C.log(f"{body.name}: created {len(hide_region_names)} empty hide-region vertex groups")

    # Step 11: vertex color channel setup is a per-artist concern (encoded via paint_hide_regions.py
    # bake step). Stub for now.

    # Step 12: export glTF
    output_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    C.set_active(rig)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = rig

    # Remove modifiers that shouldn't ship in the baked output. Keep Armature only.
    # Drop: Subdivision (we want raw decimated geometry), PreserveVolume armatures (redundant
    # with the slim rig), DataTransfer (one-shot, already applied).
    for mod in list(body.modifiers):
        if mod.type in ('SUBSURF',) or 'Preserve Volume' in mod.name:
            mod_name = mod.name  # capture before removal — StructRNA invalidates after
            body.modifiers.remove(mod)
            C.log(f"  removed modifier {mod_name}")

    # Note: the basemesh has a 'Cycles Outline' material slot that's irrelevant for our
    # cel-shader pipeline. We don't strip it here (operator context issues in background mode);
    # Godot's glTF import handles it gracefully and the cel-figure shader overrides at runtime.

    # Purge everything from the scene except body + rig before export. The basemesh source +
    # its addons leave extra meshes around (an Icosphere appeared in earlier bakes, presumably
    # an addon widget or modifier evaluation artifact). use_selection=True in the gltf export
    # isn't enough to filter these out because hierarchical-parent inclusion still grabs them.
    keep_objects = {body, rig}
    purged = []
    for obj in list(bpy.data.objects):
        if obj not in keep_objects:
            purged.append(obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
    C.log(f"  purged {len(purged)} non-essential objects before export: {purged[:8]}{'...' if len(purged) > 8 else ''}")

    # Bake region/outline data ALSO into a second UV layer (UV2). The color-attribute path is
    # unreliable through glTF export — Blender's exporter generates a default-white 'Color'
    # attribute that competes with our authored one. UV layers are mandatory glTF attributes
    # that Godot exposes as `UV2` in shaders, making the data path deterministic.
    # Encoding (UV is vec2):
    #   UV2.x = region_id / 255.0  (0.00784 = chest region 2, 1.0 = always visible region 255)
    #   UV2.y = outline thickness weight (0.0 = no outline, 1.0 = full)
    region_by_vert_final = auto_classify_hide_regions(body)
    outline_weights_final = {}
    if "Outline Thickness" in body.vertex_groups:
        vg = body.vertex_groups["Outline Thickness"]
        for v_idx, vert in enumerate(body.data.vertices):
            for g in vert.groups:
                if g.group == vg.index:
                    outline_weights_final[v_idx] = g.weight
                    break

    # Drop existing UV2 if present, recreate
    uv_layers = body.data.uv_layers
    if "UV2" in uv_layers:
        uv_layers.remove(uv_layers["UV2"])
    uv2 = uv_layers.new(name="UV2", do_init=False)
    for loop in body.data.loops:
        v_idx = loop.vertex_index
        region_id = region_by_vert_final.get(v_idx, 255)
        outline_w = outline_weights_final.get(v_idx, 1.0)
        uv2.data[loop.index].uv = (region_id / 255.0, outline_w)
    C.log(f"  baked region/outline data into UV2 ({len(body.data.loops)} corners)")

    # glTF export. Blender 5.1 renamed several export_* keys; we use the modern names.
    gltf_kwargs = dict(
        filepath=output_path,
        export_format='GLB',
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_skins=True,
        export_morph=False,
        export_animations=False,
    )
    # export_attributes covers vertex colors + custom attributes in 4.x/5.x.
    # Some Blender versions accept export_colors; try the modern name first.
    try:
        bpy.ops.export_scene.gltf(**gltf_kwargs, export_attributes=True)
    except TypeError:
        bpy.ops.export_scene.gltf(**gltf_kwargs)

    C.log(f"Exported {output_path}")

    return {
        "body_id": body_id,
        "output_path": output_path,
        "slim_rig": slim_status,
        "removed_vertex_groups": removed_vgs,
        "decimate": decimate_status,
        "body_final_polycount": len(body.data.polygons),
        "body_final_verts": len(body.data.vertices),
    }


# =============================================================================
# CLI
# =============================================================================

def _parse_argv():
    import argparse
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    p = argparse.ArgumentParser(description="Bake a body type from the Customisable Basemesh.")
    p.add_argument("--body-id", required=True, help="Body type ID (matches preset filename)")
    p.add_argument("--preset", required=True, help="Path to body type preset JSON")
    p.add_argument("--output", required=True, help="Path to output glTF (.glb)")
    p.add_argument("--no-decimate", action="store_true", help="Skip decimation step")
    p.add_argument("--drop-breast-bones", action="store_true",
                   help="Drop DEF-breast.L/R from the slim rig (dwarf male, etc.)")
    return p.parse_args(argv)


def main_cli():
    args = _parse_argv()
    result = bake_body_type(
        preset_path=args.preset,
        output_path=args.output,
        decimate=not args.no_decimate,
        drop_breast_bones=args.drop_breast_bones,
    )
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main_cli())
