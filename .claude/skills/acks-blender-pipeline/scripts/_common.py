"""
Shared utilities for the ACKS Blender pipeline scripts.

These functions assume they run inside Blender's Python environment (bpy available).
"""

import bpy
import os
import sys
import json
from contextlib import contextmanager


def log(msg, *, level="INFO"):
    """Log to stdout with a level prefix. Works in both background and interactive Blender."""
    print(f"[acks-blender-pipeline][{level}] {msg}")


def die(msg):
    """Log a fatal error and exit with non-zero status. Use only in CLI scripts."""
    log(msg, level="FATAL")
    sys.exit(1)


def get_object(name, required=True):
    """Return the object named `name`. If required and not found, raises KeyError with a clear message."""
    obj = bpy.data.objects.get(name)
    if obj is None and required:
        available = ", ".join(sorted(bpy.data.objects.keys())[:20])
        raise KeyError(f"Object '{name}' not found. Available (first 20): {available}")
    return obj


def set_active(obj):
    """Select obj and set it as the active object."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


@contextmanager
def view3d_override():
    """Context manager that yields a temp_override for a VIEW_3D area + WINDOW region.

    Use this when you need to call ops like view3d.view_axis, surfacedeform_bind (some require
    a 3D viewport context). Works in both interactive and (most) background runs.

    Usage:
        with view3d_override() as ctx:
            bpy.ops.view3d.view_axis(type='FRONT')
    """
    wm = bpy.data.window_managers[0] if bpy.data.window_managers else None
    if wm is None or not wm.windows:
        # Background mode without window context — yield bare context, ops requiring a window may fail
        yield bpy.context
        return

    window = wm.windows[0]
    screen = window.screen
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            for region in area.regions:
                if region.type == 'WINDOW':
                    with bpy.context.temp_override(window=window, screen=screen, area=area, region=region):
                        yield bpy.context
                    return
    # No VIEW_3D area present — yield bare context
    yield bpy.context


def import_fbx(path):
    """Import an FBX file. Returns the set of newly-added object names."""
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.fbx(filepath=str(path))
    after = set(bpy.data.objects.keys())
    return after - before


def import_obj(path):
    """Import an OBJ file. Returns the set of newly-added object names."""
    before = set(bpy.data.objects.keys())
    # Blender 4.x+/5.x uses wm.obj_import
    if hasattr(bpy.ops.wm, 'obj_import'):
        bpy.ops.wm.obj_import(filepath=str(path))
    else:
        bpy.ops.import_scene.obj(filepath=str(path))
    after = set(bpy.data.objects.keys())
    return after - before


def import_glb(path):
    """Import a glTF/GLB file. Returns the set of newly-added object names."""
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=str(path))
    after = set(bpy.data.objects.keys())
    return after - before


def find_modifier(obj, mod_type=None, mod_name=None):
    """Find a modifier on obj by type or name. Returns None if not found."""
    for m in obj.modifiers:
        if mod_type and m.type == mod_type:
            return m
        if mod_name and m.name == mod_name:
            return m
    return None


def remove_modifier(obj, mod_type=None, mod_name=None):
    """Remove modifier(s) matching the criteria. Returns count removed."""
    to_remove = []
    for m in obj.modifiers:
        if mod_type and m.type == mod_type:
            to_remove.append(m)
        elif mod_name and m.name == mod_name:
            to_remove.append(m)
    for m in to_remove:
        obj.modifiers.remove(m)
    return len(to_remove)


def move_modifier_before(obj, mod, target_type):
    """Reorder mod so it comes before the first modifier of target_type. No-op if already in order."""
    mod_list = list(obj.modifiers)
    mod_idx = mod_list.index(mod)
    target_idx = next((i for i, m in enumerate(mod_list) if m.type == target_type), -1)
    if target_idx < 0 or mod_idx <= target_idx:
        return
    while mod_idx > target_idx:
        obj.modifiers.move(mod_idx, mod_idx - 1)
        mod_idx -= 1


def apply_modifier(obj, mod_name):
    """Apply a modifier by name. obj must be active and in object mode."""
    set_active(obj)
    bpy.ops.object.modifier_apply(modifier=mod_name)


def load_json(path):
    """Load a JSON file as a dict."""
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def get_skill_root():
    """Return the path to the acks-blender-pipeline skill root (containing scripts/, references/)."""
    # This file lives at <root>/scripts/_common.py
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_fit_class_defaults():
    """Load the fit class default parameters from references/fit_class_defaults.json."""
    path = os.path.join(get_skill_root(), "references", "fit_class_defaults.json")
    return load_json(path)


def reset_to_empty_scene():
    """Reset Blender to an empty scene. Useful for tests and clean script invocations."""
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)


def ensure_object_mode():
    """Switch to object mode if currently in some other mode."""
    if bpy.context.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
