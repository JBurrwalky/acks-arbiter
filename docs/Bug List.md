Bug List

Status key: [FIXED 2026-06-12] / [DEFERRED]

1: [FIXED 2026-06-12] Namimg a creature or vehicle in the Character tab does not populate the new name to the inventory tab.
   → Creature rename now emits creature_inventory_updated so the inventory tab refreshes. (Vehicle rename already emitted vehicle_changed and worked.)

2: [FIXED 2026-06-12 — creature-in-dungeon] Inventory page does not allow sending items to creatures or vehicle even if they have a hitched team/capacity, either by drag and drop or by right click menu.
   → A creature shares its handler's dungeon cell, so it sat at distance 0 from you and the strict "exactly 1" adjacency rule rejected it. Same-cell is now reachable when a creature/vehicle is involved (two PCs at one cell still rejected). NOTE: a vehicle rejecting items in the *wilderness/settlement* would be a separate cause (no adjacency gate there) — capture the exact rejection text if it recurs.

3: [FIXED 2026-06-12] Party is able to move with unhitched vehicles without abandoning their vehicles.
   → Travel now prompts Leave Behind / Cancel when a vehicle can't move. "Leave behind" parks the cart + cargo as a conspicuous (heavy raid-risk) wilderness cache at the current hex, reusing the loot-cache system. FOLLOW-UP: a recovered cart is recoverable as an item only; re-deploying it into a working vehicle needs a "deploy vehicle from inventory" flow that doesn't exist yet.

4: [FIXED 2026-06-12] when equipping saddle and tack to animals, if the saddle and tack are in a stack in the owner's inventory, the whole stack equips, rather than split then equip. I.e. if the character inventory page shows saddle and tack (draft) x2 both will silently go to one animal. They must be unequipped, split, then re-equipped.
   → Creature equip now splits one unit off a stack before equipping (mirrors the PC equip path).

5: [FIXED 2026-06-12] Reaching a settlment gate node, then selecting "leave" hides the whole settlment POI menu, it does not return to the POI selection menu. This strands the player in a gray screen with no way out.
   → "Leave" now emits leave_requested, which re-shows the PoI menu (the menu is hidden on travel arrival, so hide-panel alone stranded the player).

6: [DEFERRED] The dungeon wall/ceiling culling/dithering is not good. See attached screencap.
   → Visual/shader rendering pass; warrants its own focused session.
