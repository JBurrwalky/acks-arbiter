-- Migration 194: RAW §2.2 Fanatic/Grudging loyalty DICE CARRYOVER for vassal
-- edges (rules/acore_equipment.xml:806-808). The §5.3 compliance-behavior tag
-- (migration 193) says HOW a vassal responds to requests; this adds the RAW
-- roll-to-roll state the loyalty roll itself needs: a PERSISTENT Fanatic flag
-- (+2 to all future rolls, sticky until broken) and a ONE-SHOT Grudging flag
-- (-1 to the next roll). These mirror henchman_state.is_fanatic / is_grudging
-- and are consumed by HenchmanLoyaltyResolver.resolve_loyalty_check as its
-- is_fanatic / is_grudging inputs. Non-destructive: both DEFAULT 0.
ALTER TABLE vassal_assignments ADD COLUMN loyalty_is_fanatic INTEGER NOT NULL DEFAULT 0
    CHECK(loyalty_is_fanatic IN (0, 1));
ALTER TABLE vassal_assignments ADD COLUMN loyalty_grudging_pending INTEGER NOT NULL DEFAULT 0
    CHECK(loyalty_grudging_pending IN (0, 1));
