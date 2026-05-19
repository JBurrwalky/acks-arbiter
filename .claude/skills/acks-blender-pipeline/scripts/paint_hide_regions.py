"""paint_hide_regions.py — interactive setup helper for hide-region painting.

Per gdd-character-creation-pipeline.md §8.4. Sets up a source basemesh .blend file for manual
weight painting of the 10 hide-region vertex groups. After painting, save the .blend and re-run
bake_body_type.py — painted regions take precedence over the bone-weight auto-classification.

USAGE (in Blender's Text Editor):
  1. Open the source basemesh .blend file in Blender
       e.g., Models/Customisable Female Basemesh v2.1.1/customisable female basemesh v2.1.blend
  2. Switch to the Scripting workspace (top tabs)
  3. In the Text Editor, click File > Open, navigate to this script
  4. Click "Run Script" (or press Alt+P)
  5. Body should switch to Weight Paint mode with hide_head active

WHAT THIS SCRIPT DOES:
  - Locates the body mesh (largest MESH with "Basemesh" in name)
  - Creates the 10 hide_* vertex groups if they don't exist
  - Hides distracting objects (rig widgets, cameras, lights)
  - Disables Auto Normalize (hide_* weights must not interfere with bone skinning)
  - Enables X mirror for symmetric painting
  - Switches the body to Weight Paint mode
  - Activates hide_head as the starting group

You only need to run this script ONCE per .blend file. Paint as much as you want across multiple
sessions; the vertex groups persist when you save. Re-run only if you want to reset the paint
state or you've reopened the source .blend and want the distractions re-hidden.

After painting, run bake_body_type.py from the command line as usual. Painted regions win,
unpainted areas fall back to the bone-weight heuristic.
"""

import bpy


HIDE_REGION_NAMES = [
    "hide_head",
    "hide_neck",
    "hide_chest",
    "hide_waist",
    "hide_upper_arms",
    "hide_forearms",
    "hide_hands",
    "hide_thighs",
    "hide_calves",
    "hide_feet",
]


def find_body_mesh():
    """Largest MESH object containing 'Basemesh' in its name, excluding WGT- widgets."""
    candidates = [
        o for o in bpy.data.objects
        if o.type == 'MESH' and 'Basemesh' in o.name and not o.name.startswith('WGT')
    ]
    return max(candidates, key=lambda o: len(o.data.vertices)) if candidates else None


def hide_distractions(body):
    """Hide rig, widget objects, cameras, lights so painting is unobstructed."""
    hidden = 0
    for obj in bpy.data.objects:
        if obj is body:
            continue
        if obj.type in ('ARMATURE', 'CAMERA', 'LIGHT'):
            obj.hide_viewport = True
            hidden += 1
        elif obj.name.startswith('WGT'):
            obj.hide_viewport = True
            hidden += 1
    return hidden


def ensure_hide_groups(body):
    """Create the 10 hide_* vertex groups if not already present."""
    created = []
    for name in HIDE_REGION_NAMES:
        if name not in body.vertex_groups:
            body.vertex_groups.new(name=name)
            created.append(name)
    return created


def setup_weight_paint_mode(body):
    """Switch to Weight Paint mode with sensible settings for hide-region painting."""
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body

    if bpy.context.mode != 'PAINT_WEIGHT':
        bpy.ops.object.mode_set(mode='WEIGHT_PAINT')

    ts = bpy.context.scene.tool_settings

    # CRITICAL: hide_* weights must NOT interact with bone skinning weight normalization.
    # With auto-normalize on, painting hide_chest=1.0 on a vertex would zero out its bone
    # weights — breaking skinning. Off is what we want.
    if hasattr(ts, 'use_auto_normalize'):
        ts.use_auto_normalize = False

    # X-mirror painting — paint one side and the other mirrors automatically. Several attribute
    # names exist across Blender versions; try each.
    for attr in ('symmetry_x', 'use_mirror_x'):
        if hasattr(body.data, attr):
            try:
                setattr(body.data, attr, True)
                break
            except AttributeError:
                pass

    # Activate hide_head as the initial paint target — user can switch via the vertex groups UI
    if 'hide_head' in body.vertex_groups:
        body.vertex_groups.active_index = body.vertex_groups['hide_head'].index

    # Default brush to full-weight Add at weight 1.0
    if hasattr(ts, 'unified_paint_settings'):
        try:
            ts.unified_paint_settings.weight = 1.0
        except AttributeError:
            pass


def main():
    body = find_body_mesh()
    if body is None:
        print("[paint_hide_regions] ERROR: No basemesh body found in this file.")
        print("[paint_hide_regions] Open a basemesh .blend (file containing a MESH named *Basemesh*)")
        print("[paint_hide_regions] before running this script.")
        return

    print(f"[paint_hide_regions] body mesh: {body.name} ({len(body.data.vertices)} verts)")

    created = ensure_hide_groups(body)
    if created:
        print(f"[paint_hide_regions] created {len(created)} new vertex groups: {created}")
    else:
        print("[paint_hide_regions] all 10 hide_* vertex groups already exist")

    hidden = hide_distractions(body)
    print(f"[paint_hide_regions] hid {hidden} distracting objects (rig widgets, cameras, lights)")

    setup_weight_paint_mode(body)
    print("[paint_hide_regions] switched to Weight Paint mode, X mirror on, brush weight=1.0")

    print()
    print("=" * 60)
    print("READY TO PAINT")
    print("=" * 60)
    print("In the right sidebar (Object Data Properties, green triangle icon) the 10 hide_*")
    print("vertex groups are listed. Click a group to make it active, then paint.")
    print()
    print("  hide_head        — skull, face, ears, jaw")
    print("  hide_neck        — throat, sides of neck, jaw underside")
    print("  hide_chest       — chest front + back, shoulders, upper torso to navel")
    print("  hide_waist       — hip area, lower torso navel to pelvis")
    print("  hide_upper_arms  — shoulder to elbow (both sides via X mirror)")
    print("  hide_forearms    — elbow to wrist (both sides)")
    print("  hide_hands       — wrist, palm, fingers (both sides)")
    print("  hide_thighs      — hip to knee (both sides)")
    print("  hide_calves      — knee to ankle (both sides)")
    print("  hide_feet        — ankle and foot (both sides)")
    print()
    print("Brush controls:")
    print("  - Add (default): click and drag to paint at brush weight (currently 1.0)")
    print("  - Subtract: Ctrl+click to erase")
    print("  - Brush size: F + drag, or scroll wheel")
    print("  - Brush strength: Shift+F + drag")
    print("  - X mirror: ON — paint one side, the other follows")
    print()
    print("When done, save the .blend (Ctrl+S) and re-run bake_body_type.py.")
    print("Unpainted regions fall back to the bone-weight auto-classification.")


main()
