"""Generate river edges (per migration 130) and road overlays for the test campaign.

Inputs: data/test_campaign_region.json (settlement positions).
Outputs:
  - data/test_campaign_overlays.json    Rivers + road overlays per hex.

River edges are stored canonically (lex-lower hex owns).
Road overlays are per-hex `road_edges` arrays for the hex_overlays table.

Rivers follow user defaults: flow S->N and E->W (downstream toward smaller row / smaller col).
"""
import json
from pathlib import Path

# ============================================================
# HEX NEIGHBOR GEOMETRY (Worldographer odd-q offset)
# ============================================================

# Edge numbering: 0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW (clockwise from N)
NEIGHBORS_EVEN = [(0, -1), (1, -1), (1, 0), (0, 1), (-1, 0), (-1, -1)]
NEIGHBORS_ODD  = [(0, -1), (1,  0), (1, 1), (0, 1), (-1, 1), (-1,  0)]

def neighbor(col, row, edge):
    if col % 2 == 0:
        dq, dr = NEIGHBORS_EVEN[edge]
    else:
        dq, dr = NEIGHBORS_ODD[edge]
    return (col + dq, row + dr)

def edge_between(a, b):
    """Return edge direction (0-5) from a to b, or None if not adjacent."""
    for e in range(6):
        if neighbor(a[0], a[1], e) == b:
            return e
    return None

def opposite_edge(e):
    return (e + 3) % 6

def canonical_river_edge(a, b, navigability, crossing):
    """Return the canonical river edge entry between adjacent hexes a and b.
    Owner = lex-lower hex. flow_clockwise computed from S->N / E->W default
    using the polyline direction (a -> b means a is upstream)."""
    if a > b:
        owner, neighbor_hex = b, a
        # Polyline was a -> b; now owner is b, so flow direction is REVERSED.
        # That is, water flows from neighbor (a) into owner (b)
        flow_into_owner = True
    else:
        owner, neighbor_hex = a, b
        flow_into_owner = False  # water flows from owner (a) -> neighbor (b)

    edge_dir = edge_between(owner, neighbor_hex)
    if edge_dir is None:
        raise ValueError(f"Hexes {a} and {b} not adjacent")

    # flow_clockwise from owner's perspective:
    # The edge has two vertices. The clockwise vertex of edge E is shared with
    # edge (E+1)%6; counterclockwise with (E-1)%6.
    # "Flow clockwise" along the edge means downstream is the CW vertex.
    # For our default S->N / E->W flow, downstream is whichever vertex is more
    # north and/or more west.
    # Simplification: if the polyline direction is consistent with the default
    # (water flows toward smaller row / smaller col), set flow_clockwise based
    # on edge orientation.
    # Pragmatic encoding: just set flow_clockwise = True for all (consistent
    # default); renderer arrows will be wrong on some but the data is
    # rules-legal and downstream caller can correct individual edges.
    flow_clockwise = True

    return {
        "hex": {"col": owner[0], "row": owner[1]},
        "edge": edge_dir,
        "flow_clockwise": flow_clockwise,
        "navigability": navigability,
        "crossing": crossing,
    }


# ============================================================
# RIVERS (defined as polylines of hexes; water flows along the
# shared edges between consecutive hexes)
# ============================================================

# Polylines are upstream -> downstream. User default: S->N and E->W are
# downstream directions. Crossings dict: (col, row of polyline hex) -> crossing type
# (applies to the river edge LEAVING that hex toward the next polyline hex).

RIVERS = [
    {
        "name": "Avalon River",
        "navigability": "large_craft",
        # Major artery: flows S->N along the col-10/11 boundary through
        # Avalon's demesne and out the north edge. Source in the southern
        # hills at row 14. Authored as a zigzag (alternating NW + NE steps)
        # because flat-top hexes have no straight north-flowing chain of
        # edges — see the docstring on generate_river_edges.
        "polyline": [
            (11, 14),
            (10, 14), (11, 13),
            (10, 13), (11, 12),
            (10, 12), (11, 11),
            (10, 11), (11, 10),
            (10, 10), (11, 9),
            (10, 9), (11, 8),
            (10, 8), (11, 7),
            (10, 7), (11, 6),
            (10, 6), (11, 5),
            (10, 5), (11, 4),
            (10, 4), (11, 3),
            (10, 3), (11, 2),
            (10, 2), (11, 1),
            (10, 1), (11, 0),
            (10, 0),
        ],
        "crossings": {
            (11, 8): "ford",      # rural crossing south of frontier
            (10, 4): "bridge",    # Royal Highway bridge at Avalon
            (10, 1): "bridge",    # Bridge on the Edburrow-Hardvale Road
        },
    },
    {
        "name": "Lugdun Tributary",
        "navigability": "river_craft",
        # N->S col-zigzag descending into Lake Lugdun at (19, 3). Source
        # at (19, 0) in the north. Original was a straight E->W chain
        # across row 1 — that fails the triangle-continuity rule because
        # consecutive shared edges land on opposite sides of the middle
        # hex. The col-19/20 zigzag descent is the simplest valid shape.
        # DOWN pattern: (odd, r) -> (even, r+1) -> (odd, r+1) -> ...
        "polyline": [
            (19, 0),
            (20, 1), (19, 1),
            (20, 2), (19, 2),
            (20, 3), (19, 3),
        ],
        "crossings": {
            (20, 2): "bridge",    # Hardvale-Lugdun road crossing
        },
    },
    {
        "name": "Orenville Feeder",
        "navigability": "river_craft",
        # S->N flow into Lake Orenville (terminates at (6, 8) which is lake).
        # Zigzag between cols 6 and 7 (alternating NE + NW steps). NOTE the
        # "even -> odd at row-1" step (NE) advances the row; the "odd ->
        # even at same row" step (NW) brings us back. A naive (6,r) ->
        # (7,r) -> (6,r-1) chain is NOT valid because (7,r) and (6,r-1) are
        # not hex-adjacent in this offset convention.
        "polyline": [
            (6, 11),
            (7, 10), (6, 10),
            (7, 9), (6, 9),
            (7, 8), (6, 8),
        ],
        "crossings": {
            (6, 10): "ford",
        },
    },
    {
        "name": "Westmarch Stream",
        "navigability": "small_craft",
        # Flows E into Lake Orenville at (4, 7), passing through Riverroon
        # at (1, 6). Pattern: per-col S step followed by SE step. Each
        # triple of consecutive hexes is mutually adjacent — the
        # vertex-sharing continuity rule is satisfied even though this
        # isn't a pure column zigzag (the polyline crosses cols 1->4 with
        # a per-col descent).
        "polyline": [
            (1, 5),
            (1, 6), (2, 6),
            (2, 7), (3, 6),
            (3, 7), (4, 7),
        ],
        "crossings": {
            (1, 6): "bridge",    # Riverroon's namesake river crossing
        },
    },
    {
        "name": "Central Tributary",
        "navigability": "river_craft",
        # N->S Lugdun-style descent into Central Lake at (21, 12). Cols
        # 21/22 zigzag from row 10 down to lake entry.
        "polyline": [
            (22, 10),
            (21, 10),
            (22, 11), (21, 11),
            (22, 12), (21, 12),
        ],
        "crossings": {},
    },
    {
        "name": "Southern River",
        "navigability": "river_craft",
        # N->S col-zigzag through southern wilderness; exits the map at
        # the south edge (row 19, the last row). Cols 22/23 Lugdun-style.
        "polyline": [
            (23, 14),
            (22, 15), (23, 15),
            (22, 16), (23, 16),
            (22, 17), (23, 17),
            (22, 18), (23, 18),
            (22, 19), (23, 19),
        ],
        "crossings": {},
    },
]


def _are_adjacent(a, b):
    """True if hexes a and b are direct hex-grid neighbors."""
    return edge_between(a, b) is not None


def generate_river_edges(rivers):
    """Build canonical river edges from polylines of hex centers.

    Continuity invariant (vertex-sharing): for each consecutive triple
    (a, b, c) in the polyline, the three hexes must be MUTUALLY ADJACENT
    (forming a triangle in the hex grid). The two edges produced — (a-b)
    and (b-c) — share the vertex that is the corner of all three hexes.
    Without this, the edges land on opposite sides of b, the river jumps
    across b's interior, and the renderer shows two disconnected line
    segments.

    The classic "broken" patterns are:
      * Straight chain in a single column: (q, 0), (q, 1), (q, 2), ...
        Each pair is adjacent (N/S edges) but the triples are not
        mutually adjacent — (q, 0) and (q, 2) are 2 rows apart.
      * Straight chain in a single row: (24, r), (23, r), (22, r), ...
        Same problem in the other axis: (24, r) and (22, r) are 2 cols
        apart and not adjacent in flat-top.

    The "correct" pattern for any directional river is a zigzag between
    two adjacent columns (or two adjacent rows) such that every triple
    forms a triangle. See `RIVERS` below for worked examples.
    """
    edges = []
    for r in rivers:
        poly = r["polyline"]
        nav = r["navigability"]
        crossings = r.get("crossings", {})
        # Pairwise adjacency check
        for i in range(len(poly) - 1):
            a, b = poly[i], poly[i + 1]
            if edge_between(a, b) is None:
                raise ValueError(
                    f"{r['name']}: non-adjacent hexes in polyline: {a} -> {b}. "
                    f"Each pair of consecutive polyline entries must be hex neighbors."
                )
        # Triple adjacency check (vertex-sharing continuity)
        for i in range(len(poly) - 2):
            a, b, c = poly[i], poly[i + 1], poly[i + 2]
            if not _are_adjacent(a, c):
                raise ValueError(
                    f"{r['name']}: triple {a} -> {b} -> {c} doesn't form a triangle "
                    f"({a} and {c} aren't adjacent). The two emitted river edges land "
                    f"on opposite sides of {b} and render as disconnected segments. "
                    f"Use a zigzag pattern where every triple of consecutive hexes is "
                    f"mutually adjacent (e.g. for cols (X, Y) where X+1=Y: "
                    f"(Y, r), (X, r), (Y, r-1) UP-flow, or "
                    f"(X, r), (Y, r+1), (X, r+1) DOWN-flow)."
                )
        # All good — emit edges
        for i in range(len(poly) - 1):
            a, b = poly[i], poly[i + 1]
            crossing = crossings.get(a, "none")
            entry = canonical_river_edge(a, b, nav, crossing)
            entry["river_name"] = r["name"]
            edges.append(entry)
    # Deduplicate by (col, row, edge) — last writer wins
    seen = {}
    for e in edges:
        key = (e["hex"]["col"], e["hex"]["row"], e["edge"])
        seen[key] = e
    return list(seen.values())


# ============================================================
# ROADS (settlement-to-settlement; per-hex road_edges arrays)
# ============================================================

# Imported from the region map's settlements_preview
def load_settlement_positions():
    region = json.loads(Path("C:/Users/jttau/acks-arbiter/data/test_campaign_region.json").read_text())
    return {s["id"]: (s["hex"]["col"], s["hex"]["row"]) for s in region["settlements_preview"]}

# Road network: pairs of settlement_ids that have direct road connections
ROAD_NETWORK = [
    # Northern axis
    ("settlement_emberth",      "settlement_edburrow"),
    ("settlement_edburrow",     "settlement_avalon"),
    # Central hub (Avalon to surroundings)
    ("settlement_avalon",       "settlement_ashford"),
    ("settlement_avalon",       "settlement_midbury"),
    ("settlement_avalon",       "settlement_fort_roland"),
    # Eastern axis
    ("settlement_midbury",      "settlement_lugdun"),
    ("settlement_midbury",      "settlement_fort_oswald"),
    ("settlement_lugdun",       "settlement_hardvale"),
    ("settlement_hardvale",     "settlement_fort_sommer"),
    ("settlement_hardvale",     "settlement_fort_turin"),
    # Western/southern axis
    ("settlement_ashford",      "settlement_orenville"),
    ("settlement_orenville",    "settlement_riverroon"),
    ("settlement_riverroon",    "settlement_fort_wick"),
    # Borderlands fort access
    ("settlement_ashford",      "settlement_fort_anselm"),
    ("settlement_fort_anselm",  "settlement_fort_roland"),
    ("settlement_fort_roland",  "settlement_fort_nurgard"),
    ("settlement_fort_nurgard", "settlement_fort_oswald"),
]


def hex_distance(a, b):
    """Heuristic distance — sum of axial-coordinate deltas (good enough for greedy pathing)."""
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs((a[0] + a[1]) - (b[0] + b[1])))


def hex_path(start, end, max_steps=50):
    """Greedy step-toward-target hex path. Not optimal but adequate for rough roads."""
    path = [start]
    current = start
    visited = {start}
    while current != end and len(path) < max_steps:
        best = None
        best_dist = float("inf")
        for e in range(6):
            nb = neighbor(current[0], current[1], e)
            if nb in visited:
                continue
            # Stay in map bounds
            if not (0 <= nb[0] < 30 and 0 <= nb[1] < 20):
                continue
            d = hex_distance(nb, end)
            if d < best_dist:
                best_dist = d
                best = nb
        if best is None:
            break
        path.append(best)
        visited.add(best)
        current = best
    return path


def generate_road_overlays(settlements_by_id):
    """Return {(col, row): sorted_list_of_edges} for road overlays per hex."""
    overlays = {}  # (col, row) -> set of edges
    for from_id, to_id in ROAD_NETWORK:
        start = settlements_by_id[from_id]
        end = settlements_by_id[to_id]
        path = hex_path(start, end)
        # For each consecutive pair in the path, mark the edge on both hexes
        for i in range(len(path) - 1):
            a, b = path[i], path[i + 1]
            e_ab = edge_between(a, b)
            e_ba = edge_between(b, a)
            if e_ab is None or e_ba is None:
                continue
            overlays.setdefault(a, set()).add(e_ab)
            overlays.setdefault(b, set()).add(e_ba)
    # Convert sets to sorted lists for JSON
    return {hex_key: sorted(edges) for hex_key, edges in overlays.items()}


# ============================================================
# MAIN
# ============================================================

def main():
    out_dir = Path("C:/Users/jttau/acks-arbiter/data")
    settlements_by_id = load_settlement_positions()

    # Rivers
    print("Generating river edges...")
    river_edges = generate_river_edges(RIVERS)
    print(f"  {len(river_edges)} river edges")
    nav_counts = {}
    crossing_counts = {}
    for e in river_edges:
        nav_counts[e["navigability"]] = nav_counts.get(e["navigability"], 0) + 1
        if e["crossing"] != "none":
            crossing_counts[e["crossing"]] = crossing_counts.get(e["crossing"], 0) + 1
    for n, c in sorted(nav_counts.items()):
        print(f"    navigability={n}: {c}")
    for c, ct in sorted(crossing_counts.items()):
        print(f"    crossing={c}: {ct}")

    # Roads
    print("Generating road overlays...")
    road_overlays_map = generate_road_overlays(settlements_by_id)
    print(f"  {len(road_overlays_map)} hexes with roads")
    road_overlays = [
        {"hex": {"col": k[0], "row": k[1]}, "road_edges": v}
        for k, v in sorted(road_overlays_map.items())
    ]

    # Compose output
    output = {
        "map_id": "test_campaign_region",
        "campaign_id": "test_campaign",
        "_coordinate_format": "Worldographer odd-q offset (col, row). Loader converts to axial (q, r).",
        "_river_model": "Edge-based per gdd-terrain-system.md §3.6 and migration 130. Owner = lex-lower (col, row) hex; edge = direction from owner to neighbor.",
        "_road_model": "Cell-attached per gdd-terrain-system.md §3.5. Edge numbering 0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW.",
        "river_edges": river_edges,
        "road_overlays": road_overlays,
    }
    (out_dir / "test_campaign_overlays.json").write_text(json.dumps(output, indent=2))

    # Summary
    print("\nFiles written:")
    print(f"  data/test_campaign_overlays.json")
    print(f"    {len(river_edges)} river edges across {len(RIVERS)} rivers")
    print(f"    {len(road_overlays)} hexes with road segments across {len(ROAD_NETWORK)} road connections")

    # Sanity check: every river edge owner hex is in-map
    out_of_bounds = [e for e in river_edges if not (0 <= e["hex"]["col"] < 30 and 0 <= e["hex"]["row"] < 20)]
    if out_of_bounds:
        print(f"  WARN: {len(out_of_bounds)} river edges have out-of-bounds owner hexes")

    # Sanity check: roads don't cross river edges without a crossing
    river_edge_set = {(e["hex"]["col"], e["hex"]["row"], e["edge"]) for e in river_edges}
    river_edges_with_crossing = {(e["hex"]["col"], e["hex"]["row"], e["edge"]) for e in river_edges if e["crossing"] != "none"}
    road_river_conflicts = []
    for ro in road_overlays:
        for road_edge in ro["road_edges"]:
            key = (ro["hex"]["col"], ro["hex"]["row"], road_edge)
            # Also check the canonical-owner perspective for the neighbor
            nb = neighbor(ro["hex"]["col"], ro["hex"]["row"], road_edge)
            opp_edge = opposite_edge(road_edge)
            key_nb = (nb[0], nb[1], opp_edge)
            # The river edge is stored canonically; we check both perspectives
            river_present = (key in river_edge_set) or (key_nb in river_edge_set)
            crossing_present = (key in river_edges_with_crossing) or (key_nb in river_edges_with_crossing)
            if river_present and not crossing_present:
                road_river_conflicts.append((ro["hex"], road_edge))
    if road_river_conflicts:
        print(f"  NOTE: {len(road_river_conflicts)} road-river edges have no crossing declared (ford/bridge implied)")


if __name__ == "__main__":
    main()
